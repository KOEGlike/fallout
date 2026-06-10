require "aws-sdk-s3"
require "net/http"
require "digest"
require "tempfile"
require "json"
require "open3"
require "marcel"

class LapseArchiveService
  class Error < StandardError; end

  PREFIX = "lapse-archive".freeze
  SCHEMA_VERSION = 1
  MAX_REDIRECTS = 3

  # Returns :archived, or :skipped when already archived and not forced.
  # Lapse is semi-unstable, so we validate the API data and probe the downloaded
  # footage BEFORE uploading or stamping archived_at — a corrupt fetch raises and
  # leaves the row un-archived so a later backfill retries it (fail-closed).
  def archive!(lapse_timelapse, force: false)
    return :skipped if lapse_timelapse.archived_at.present? && !force

    # Full raw fetch_timelapse JSON. The model handles user-token → program-key fallback,
    # so this works when backfilling across every user. nil = Lapse down / timelapse gone
    # (malformed JSON also surfaces as nil from LapseService).
    raw = lapse_timelapse.fetch_data

    # If Lapse returned a body, it must be a Hash carrying the linchpin field; otherwise
    # it's a corrupt/partial response we refuse to treat as a valid snapshot.
    if raw.present? && !(raw.is_a?(Hash) && raw["playbackUrl"].present?)
      raise Error, "Corrupt Lapse API data for ##{lapse_timelapse.id} (missing playbackUrl)"
    end

    # Prefer the freshest URLs from the live response; fall back to our cached columns.
    playback_url  = raw&.dig("playbackUrl").presence || lapse_timelapse.playback_url.presence
    thumbnail_url = raw&.dig("thumbnailUrl").presence || lapse_timelapse.thumbnail_url.presence

    raise Error, "No playback_url to archive for LapseTimelapse ##{lapse_timelapse.id}" if playback_url.blank?

    id     = lapse_timelapse.lapse_timelapse_id
    prefix = "#{PREFIX}/#{id}"

    video = download(playback_url, default_ext: video_ext(raw, playback_url))
    video[:probe_duration] = verify_video!(video)

    thumb = thumbnail_url ? download(thumbnail_url, default_ext: thumb_ext(thumbnail_url)) : nil
    verify_thumbnail!(thumb) if thumb

    video_key = "#{prefix}/video#{video[:ext]}"
    thumb_key = thumb && "#{prefix}/thumbnail#{thumb[:ext]}"

    upload_file(video_key, video)
    upload_file(thumb_key, thumb) if thumb

    metadata = {
      schema_version: SCHEMA_VERSION,
      archived_at: Time.current.utc.iso8601,
      lapse_timelapse_id: id,
      source: raw, # full raw API response — future-proof
      db_record: lapse_timelapse.attributes, # cached row incl. inactive_segments, owner_*, duration
      assets: {
        video: asset_manifest(playback_url, video_key, video),
        thumbnail: asset_manifest(thumbnail_url, thumb_key, thumb)
      }
    }
    upload_json("#{prefix}/metadata.json", metadata)

    lapse_timelapse.update!(
      archived_at: Time.current,
      archive_video_byte_size: video[:byte_size],
      archive_checksum: video[:sha256]
    )
    :archived
  rescue StandardError => e
    ErrorReporter.capture_exception(e, contexts: {
      lapse_archive: { lapse_timelapse_id: lapse_timelapse.lapse_timelapse_id }
    })
    raise
  ensure
    video[:tempfile].close! if video && !video[:tempfile].closed?
    thumb[:tempfile].close! if thumb && !thumb[:tempfile].closed?
  end

  private

  def asset_manifest(source_url, key, asset)
    return { source_url: source_url, archived: false } unless asset

    {
      source_url: source_url,
      key: key,
      content_type: asset[:content_type],
      byte_size: asset[:byte_size],
      sha256: asset[:sha256],
      ffprobe_duration: asset[:probe_duration]
    }.compact
  end

  # Confirm the downloaded footage is a real, readable video — catches truncated
  # downloads and HTML error pages a flaky CDN may serve. Returns the probed duration.
  def verify_video!(asset)
    raise Error, "Empty video download" if asset[:byte_size].to_i.zero?

    asset[:tempfile].flush
    out, status = Open3.capture2e(
      "ffprobe", "-v", "error",
      "-show_entries", "format=duration",
      "-show_entries", "stream=codec_type",
      "-of", "json", asset[:tempfile].path
    )
    raise Error, "ffprobe failed on archived video: #{out.to_s.truncate(200)}" unless status.success?

    probe = JSON.parse(out)
    has_video = Array(probe["streams"]).any? { |s| s["codec_type"] == "video" }
    duration = probe.dig("format", "duration").to_f

    raise Error, "Archived video has no video stream" unless has_video
    raise Error, "Archived video has non-positive duration (#{duration})" unless duration.positive?

    duration
  end

  # Confirm the thumbnail bytes actually decode as an image (not an error page).
  def verify_thumbnail!(asset)
    raise Error, "Empty thumbnail download" if asset[:byte_size].to_i.zero?

    asset[:tempfile].rewind
    mime = Marcel::MimeType.for(asset[:tempfile])
    raise Error, "Archived thumbnail is not an image (#{mime})" unless mime.to_s.start_with?("image/")
  ensure
    asset[:tempfile].rewind
  end

  # Stream a URL to a tempfile, following redirects, hashing + sizing as we write.
  # Mirrors TimelapseActivityChecker#download_from_url but streams the body to disk.
  def download(url, default_ext:, redirects_left: MAX_REDIRECTS)
    uri = URI.parse(url)
    tempfile = Tempfile.new([ "lapse_archive_", default_ext ])
    tempfile.binmode
    digest = Digest::SHA256.new
    size = 0
    content_type = nil
    redirect_to = nil

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                    open_timeout: 5, read_timeout: 60) do |http|
      http.request(Net::HTTP::Get.new(uri)) do |res|
        case res
        when Net::HTTPRedirection
          redirect_to = res["location"]
        when Net::HTTPSuccess
          content_type = res["content-type"]
          res.read_body do |chunk|
            tempfile.write(chunk)
            digest.update(chunk)
            size += chunk.bytesize
          end
        else
          raise Error, "Download failed (HTTP #{res.code}) for #{url}"
        end
      end
    end

    if redirect_to
      tempfile.close!
      raise Error, "Too many redirects for #{url}" if redirects_left <= 0

      return download(redirect_to, default_ext: default_ext, redirects_left: redirects_left - 1)
    end

    tempfile.flush
    tempfile.rewind
    { tempfile: tempfile, ext: default_ext, content_type: content_type,
      byte_size: size, sha256: digest.hexdigest }
  rescue StandardError
    tempfile.close! if tempfile && !tempfile.closed?
    raise
  end

  def upload_file(key, asset)
    asset[:tempfile].rewind
    client.put_object(
      bucket: bucket,
      key: key,
      body: asset[:tempfile],
      content_type: asset[:content_type].presence || "application/octet-stream"
    )
  end

  def upload_json(key, hash)
    client.put_object(bucket: bucket, key: key,
                      body: JSON.generate(hash), content_type: "application/json")
  end

  def video_ext(raw, url)
    kind = raw&.dig("videoContainerKind").presence
    return ".#{kind.delete_prefix('.')}" if kind

    File.extname(URI.parse(url).path).presence || ".mp4"
  end

  def thumb_ext(url)
    File.extname(URI.parse(url).path).presence || ".jpg"
  end

  def bucket
    ENV.fetch("R2_BUCKET")
  end

  # Self-managed client built from the SAME env as the :r2 ActiveStorage service
  # (config/storage.yml). Deliberately does NOT touch ActiveStorage's tables/service,
  # and writes only under the lapse-archive/ prefix, so it cannot collide with or
  # mutate ActiveStorage's random-keyed blobs. The checksum opts match storage.yml —
  # R2 rejects aws-sdk's newer default checksums.
  def client
    @client ||= Aws::S3::Client.new(
      access_key_id: ENV.fetch("R2_ACCESS_KEY_ID"),
      secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
      region: "auto",
      endpoint: ENV.fetch("R2_ENDPOINT"),
      force_path_style: true,
      request_checksum_calculation: "when_required",
      response_checksum_validation: "when_required"
    )
  end
end
