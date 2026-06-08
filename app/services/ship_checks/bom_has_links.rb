# frozen_string_literal: true

module ShipChecks
  module BomHasLinks
    DEFINITION = { key: :bom_has_links, label: "BOM links work", deps: [ :bom_content ], visibility: :user }.freeze

    # Bound how many user-supplied URLs we probe so a BOM stuffed with
    # thousands of links can't turn a worker into an outbound request engine.
    MAX_CHECKED = 30

    def self.call(ctx)
      content = ctx.bom_content
      if content.nil?
        return ShipCheckService::CheckResult.new(
          key: "bom_has_links", label: DEFINITION[:label],
          status: :skipped, message: "No BOM file found", visibility: :user
        )
      end

      # An unparseable CSV can't be link-scanned reliably — defer to the
      # formatting check rather than wrongly reporting "add purchase links".
      if ctx.bom_csv == :malformed
        return ShipCheckService::CheckResult.new(
          key: "bom_has_links", label: DEFINITION[:label],
          status: :skipped, message: "Couldn't read BOM to check links", visibility: :user
        )
      end

      # Extract URLs respecting CSV quoting — quoted fields may contain commas that are part of the URL.
      # \s* after the delimiter tolerates ", " / " ," spacing so padded BOMs still surface their links.
      urls = content.scan(%r{"(https?://[^"]+)"|(?:^|,)\s*(https?://[^\s,<>]+)})
                    .flatten.compact.map { |u| u.chomp(".") }.uniq
      if urls.empty?
        return ShipCheckService::CheckResult.new(
          key: "bom_has_links", label: DEFINITION[:label],
          status: :failed, message: "Add purchase links to your Bill of Materials so others can source parts",
          visibility: :user
        )
      end

      checked = urls.first(MAX_CHECKED)
      broken = checked.filter_map { |url| url unless resolves?(url) }
      if broken.any?
        ShipCheckService::CheckResult.new(
          key: "bom_has_links",
          label: DEFINITION[:label],
          status: :warn,
          message: "#{broken.size} of #{checked.size} BOM links are broken: #{broken.first(3).join(", ")}",
          visibility: :user
        )
      else
        ShipCheckService::CheckResult.new(
          key: "bom_has_links", label: DEFINITION[:label],
          status: :passed, message: nil, visibility: :user
        )
      end
    end

    def self.resolves?(url, retries: 2)
      uri = URI(url)
      return false unless uri.is_a?(URI::HTTP) && uri.host

      # SSRF guard: BOM URLs are user-supplied. Resolve the host to a public IP
      # and pin the connection to it so a malicious BOM can't reach cloud
      # metadata (169.254.169.254) or internal services via DNS rebinding.
      safe_ip = ShipChecks::SafeHttp.resolve_safe_ip(uri.host)
      return false unless safe_ip

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.ipaddr = safe_ip
      http.open_timeout = 5
      http.read_timeout = 5

      response = http.start do |conn|
        # Try HEAD first, fall back to GET — some sites block HEAD requests
        res = conn.head(uri.request_uri)
        res.is_a?(Net::HTTPSuccess) || res.is_a?(Net::HTTPRedirection) ? res : conn.get(uri.request_uri)
      end
      return true if response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPRedirection)
      # Cloudflare bot challenges return 403 with a "Just a moment..." interstitial
      # we can't solve — lean safe and treat the link as valid rather than failing the user.
      response.code.to_i == 403 && response.body.to_s.include?("Just a moment...")
    rescue StandardError
      retry if (retries -= 1) >= 0
      false
    end
  end
end
