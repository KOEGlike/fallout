# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

# IO-like log device that ships formatted log lines to Uptrace via OTLP/HTTP.
# Plugged in via broadcast_to so stdout output is unaffected — this is a copy.
# Drops on queue overflow rather than blocking request threads.
class UptraceLogDevice
  ENDPOINT = "https://api.uptrace.dev/v1/logs"
  BATCH_SIZE = 100
  FLUSH_INTERVAL = 2 # seconds
  QUEUE_SIZE = 10_000
  HTTP_TIMEOUT = 10 # seconds

  def initialize(dsn:, service_name:, environment:)
    @dsn = dsn
    @service_name = service_name
    @environment = environment
    @queue = SizedQueue.new(QUEUE_SIZE)
    @uri = URI(ENDPOINT)
    start_worker
  end

  def write(message)
    @queue.push([ Time.now, message.to_s ], true)
    nil
  rescue StandardError
    nil
  end

  def close
    @queue.close
    @worker&.join(5)
  end

  private

  def start_worker
    @worker = Thread.new do
      Thread.current.name = "uptrace-logger"
      loop do
        batch = drain_batch
        break if batch.nil?
        next if batch.empty?
        ship(batch)
      end
    end
  end

  def drain_batch
    batch = []
    deadline = Time.now + FLUSH_INTERVAL
    while batch.size < BATCH_SIZE
      remaining = deadline - Time.now
      break if remaining <= 0
      item = @queue.pop(timeout: remaining)
      return nil if item.nil? && @queue.closed?
      batch << item if item
    end
    batch
  end

  def ship(batch)
    body = {
      resourceLogs: [ {
        resource: {
          attributes: [
            { key: "service.name", value: { stringValue: @service_name } },
            { key: "deployment.environment", value: { stringValue: @environment } }
          ]
        },
        scopeLogs: [ {
          logRecords: batch.map { |time, msg|
            {
              timeUnixNano: (time.to_f * 1_000_000_000).to_i.to_s,
              body: { stringValue: msg }
            }
          }
        } ]
      } ]
    }

    req = Net::HTTP::Post.new(@uri)
    req["Content-Type"] = "application/json"
    req["uptrace-dsn"] = @dsn
    req.body = JSON.generate(body)

    Net::HTTP.start(@uri.host, @uri.port, use_ssl: true) do |http|
      http.open_timeout = HTTP_TIMEOUT
      http.read_timeout = HTTP_TIMEOUT
      http.request(req)
    end
  rescue StandardError
    nil
  end
end
