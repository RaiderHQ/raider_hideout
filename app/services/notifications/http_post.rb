require "net/http"

module Notifications
  module HttpPost
    TIMEOUT = 10
    NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error, SocketError,
                       SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError, Net::HTTPBadResponse ].freeze
    MAX_RETRY_AFTER = 3600
    MAX_BODY = 4000
    MAX_DETAIL = 200

    def self.call(url, payload)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http.write_timeout = TIMEOUT
      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = payload.to_json
      handle(http.request(request))
    rescue URI::InvalidURIError
      raise PermanentError, "invalid webhook URL"
    rescue *NETWORK_ERRORS => e
      raise RetryableError, "#{e.class}: #{e.message}"
    end

    def self.handle(response)
      code = response.code.to_i
      body = response.body.to_s[0, MAX_BODY]
      case code
      when 200..299 then nil
      when 429 then raise RetryableError.new("HTTP 429", retry_after: retry_after(response["Retry-After"]), body: body)
      when 500..599 then raise RetryableError.new("HTTP #{code}", body: body)
      else raise PermanentError.new("HTTP #{code}", body: body)
      end
    end

    # Builds the final error: redact the raw body first, then truncate, so a secret
    # straddling the cut can never leak a prefix.
    def self.sanitized(error, channel)
      message = error.message
      detail = error.body.present? ? channel.redact(error.body)[0, MAX_DETAIL] : nil
      message = "#{message}: #{detail}" if detail.present?
      message = channel.redact(message)
      if error.is_a?(RetryableError)
        RetryableError.new(message, retry_after: error.retry_after)
      else
        PermanentError.new(message)
      end
    end

    def self.retry_after(value)
      return nil if value.blank?

      seconds = Integer(value, exception: false)
      seconds ||= begin
        (Time.httpdate(value) - Time.now).ceil
      rescue ArgumentError
        nil
      end
      seconds&.clamp(0, MAX_RETRY_AFTER)
    end
  end
end
