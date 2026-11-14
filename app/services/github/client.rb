require "net/http"

module Github
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
      check_parts!(owner, repo)
      request(Net::HTTP::Get, "/repos/#{owner}/#{repo}")
    end

    # GET /repos/{owner}/{repo}/actions/workflows/{workflow}: needs Actions: read.
    def workflow(owner, repo, workflow)
      check_parts!(owner, repo)
      check_workflow!(workflow)
      request(Net::HTTP::Get, "/repos/#{owner}/#{repo}/actions/workflows/#{workflow}")
    end

    # POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun-failed-jobs: failed jobs only, empty body.
    def rerun_failed_jobs(owner, repo, run_id)
      check_parts!(owner, repo)
      raise Error, "invalid run" unless Repository::RUN_ID.match?(run_id.to_s)

      request(Net::HTTP::Post, "/repos/#{owner}/#{repo}/actions/runs/#{run_id}/rerun-failed-jobs")
    end

    # POST /repos/{owner}/{repo}/actions/workflows/{workflow}/dispatches: Actions: write. The
    # body is the ref, return_run_details, and at most the one tag input; nothing else is sent.
    def dispatch_workflow(owner, repo, workflow, ref:, inputs: {})
      check_parts!(owner, repo)
      check_workflow!(workflow)
      raise Error, "invalid ref" unless ref.is_a?(String) && RunRequest::REF_FORMAT.match?(ref)

      body = { ref: ref, return_run_details: true }
      body[:inputs] = checked_inputs(inputs) if inputs.present?
      response, parsed = exchange(Net::HTTP::Post, "/repos/#{owner}/#{repo}/actions/workflows/#{workflow}/dispatches", body: body)
      return response unless response.status.is_a?(Integer) && response.status.between?(200, 299)

      run_id, html_url = run_details(parsed, owner, repo)
      response.with(run_id: run_id, html_url: html_url)
    end

    private

    def checked_inputs(inputs)
      raise Error, "invalid inputs" unless inputs.is_a?(Hash) && inputs.size == 1

      key, value = inputs.first
      unless key.is_a?(String) && CiAccess::TAG_INPUT_FORMAT.match?(key) && value.is_a?(String) && RunRequest::TAGS_FORMAT.match?(value)
        raise Error, "invalid inputs"
      end

      { key => value }
    end

    # The run id only when it is an Integer that is a valid run id; the html_url only when it is
    # that run's page on github.com (any casing of this repository), else rebuilt from the parts.
    def run_details(parsed, owner, repo)
      id = parsed&.dig("workflow_run_id")
      return [ nil, nil ] unless id.is_a?(Integer) && Repository::RUN_ID.match?(id.to_s)

      run_id = id.to_s
      built = "https://github.com/#{owner}/#{repo}/actions/runs/#{run_id}"
      url = parsed["html_url"]
      pattern = %r{\A#{Regexp.escape(built)}(/[A-Za-z0-9/_.-]*)?\z}i
      [ run_id, url.is_a?(String) && pattern.match?(url) ? url : built ]
    end

    def check_parts!(owner, repo)
      raise Error, "invalid repository" unless Repository.valid_part?(owner) && Repository.valid_part?(repo)
    end

    def check_workflow!(workflow)
      raise Error, "invalid workflow" unless workflow.is_a?(String) && CiAccess::WORKFLOW_FORMAT.match?(workflow)
    end

    def request(verb, path) = exchange(verb, path).first

    # [Response, the parsed JSON object or nil]. The body, when given, is sent as JSON.
    def exchange(verb, path, body: nil)
      raise Error, "invalid token" unless CiAccess::TOKEN_FORMAT.match?(@token.to_s)

      http = Net::HTTP.new(HOST, 443)
      http.use_ssl = true
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      http.write_timeout = TIMEOUT
      http.max_retries = 0
      http_request = verb.new(path, body ? headers.merge("Content-Type" => "application/json") : headers)
      http_request.body = JSON.generate(body) if body
      response = http.request(http_request)
      parsed = parse(response.body)
      [ Response.new(status: response.code.to_i, message: message_from(parsed)), parsed ]
    rescue *NETWORK_ERRORS
      [ Response.new(status: :network, message: nil), nil ]
    end

    def headers
      { "Authorization" => "Bearer #{@token}", "Accept" => "application/vnd.github+json",
        "X-GitHub-Api-Version" => "2022-11-28", "User-Agent" => "Raider-Hideout" }
    end

    def parse(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : nil
    rescue JSON::ParserError, TypeError
      nil
    end

    def message_from(parsed)
      message = parsed&.dig("message")
      return nil unless message.is_a?(String)

      CiAccess.mask(message, @token)[0, MAX_MESSAGE]
    end
  end
end
