# frozen_string_literal: true

module ShipChecks
  module BomFormatting
    DEFINITION = { key: :bom_formatting, label: "BOM is properly formatted", deps: [ :bom_content ], visibility: :user }.freeze

    def self.call(ctx)
      rows = ctx.bom_csv

      if rows == :no_csv
        return ShipCheckService::CheckResult.new(
          key: "bom_formatting", label: DEFINITION[:label],
          status: :skipped, message: "No CSV Bill of Materials found", visibility: :user
        )
      end

      if rows == :malformed
        return ShipCheckService::CheckResult.new(
          key: "bom_formatting", label: DEFINITION[:label],
          status: :failed,
          message: "We couldn't read your Bill of Materials — make sure it's a valid CSV (one part per row, comma-separated)",
          visibility: :user
        )
      end

      if padded_delimiter?(rows)
        return ShipCheckService::CheckResult.new(
          key: "bom_formatting", label: DEFINITION[:label],
          status: :warn,
          message: "Use \",\" as your BOM delimiter (no spaces around commas)",
          visibility: :user
        )
      end

      ShipCheckService::CheckResult.new(
        key: "bom_formatting", label: DEFINITION[:label],
        status: :passed, message: nil, visibility: :user
      )
    end

    # A cell that begins or ends with whitespace is the fingerprint of a
    # ", " / " ," delimiter — quoted fields parse without that artifact. We
    # require a majority of rows to show it so a stray padded value doesn't trip.
    def self.padded_delimiter?(rows)
      data = rows.reject { |row| row.compact.all? { |cell| cell.to_s.strip.empty? } }
      return false if data.empty?

      padded = data.count do |row|
        row.compact.any? { |cell| cell != cell.strip && !cell.strip.empty? }
      end
      padded * 2 >= data.size
    end
  end
end
