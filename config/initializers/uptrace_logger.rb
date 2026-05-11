# frozen_string_literal: true

# Broadcasts Rails.logger output to Uptrace in production. stdout is unchanged;
# Uptrace receives a copy via an async, in-memory buffered HTTP shipper.
if Rails.env.production? && ENV["UPTRACE_DSN"].present?
  Rails.application.config.after_initialize do
    begin
      device = UptraceLogDevice.new(
        dsn: ENV["UPTRACE_DSN"],
        service_name: "fallout",
        environment: Rails.env
      )
      uptrace_logger = ActiveSupport::TaggedLogging.logger(device)
      uptrace_logger.level = Rails.logger.level
      Rails.logger.broadcast_to(uptrace_logger)
    rescue StandardError => e
      Rails.logger.warn("Uptrace logger setup failed: #{e.class}: #{e.message}")
    end
  end
end
