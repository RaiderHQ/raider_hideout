require "net/http"

module Github
  Response = Data.define(:status, :message)

  # Minimal GitHub REST client. Fixed host, no redirects, 10 s timeouts. The token is only
  # ever in the Authorization header; messages from GitHub are redacted, then truncated.
  class Client
    class Error < StandardError; end

    HOST = "api.github.com".freeze
    TIMEOUT = 10
    MAX_MESSAGE = 200
    NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error, SocketError,
                       SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError, Net::HTTPBadResponse,
                       Net::ProtocolError ].freeze

    def initialize(token)
      @token = token
    end

    def inspect = "#<Github::Client token=[REDACTED]>"

    # GET /repos/{owner}/{repo}: needs only Metadata: read.
    def repository(owner, repo)
      raise Error, "invalid repository" unless Repository.valid_part?(owner) && Repository.valid_part?(repo)

      request(Net::HTTP::Get, "/repos/#{owner}/#{repo}")
    end

    private

    def request(verb, path)
      http = Net::HTTP.new(HOST, 443)
      http.use_ssl = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http.write_timeout = TIMEOUT
      http.max_retries = 0
      response = http.request(verb.new(path, headers))
      Response.new(status: response.code.to_i, message: message_from(response.body))
    rescue *NETWORK_ERRORS
      Response.new(status: :network, message: nil)
    end

    def headers
      { "Authorization" => "Bearer #{@token}", "Accept" => "application/vnd.github+json",
        "X-GitHub-Api-Version" => "2022-11-28", "User-Agent" => "Raider-Hideout" }
    end

    def message_from(body)
      message = JSON.parse(body.to_s)["message"]
      return nil unless message.is_a?(String)

      message.gsub(@token) { "[token]" }[0, MAX_MESSAGE]
    rescue JSON::ParserError, TypeError, NoMethodError
      nil
    end
  end
end
