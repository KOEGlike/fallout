require "faraday"
require "json"

module AttendService
  class Error < StandardError; end
  class ApiError < Error
    attr_reader :status

    def initialize(msg, status: nil)
      super(msg)
      @status = status
    end
  end

  ATTEND_URL = "https://attend.hackclub.com/api/v1/events/fallout/participants"

  module_function

  def add_participant(first_name:, last_name:, email:)
    api_key = ENV.fetch("ATTEND_API_KEY") { raise Error, "ATTEND_API_KEY is not configured" }

    conn = Faraday.new do |f|
      f.request :json
    end

    response = conn.post(ATTEND_URL) do |req|
      req.headers["Authorization"] = "Bearer #{api_key}"
      req.headers["Content-Type"] = "application/json"
      req.body = { first_name: first_name, last_name: last_name, email: email }.to_json
    end

    raise ApiError.new("Attend API error: #{response.status}", status: response.status) unless response.success? || response.status == 409

    JSON.parse(response.body)
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError => e
    raise Error, "Attend API connection failed: #{e.message}"
  end
end
