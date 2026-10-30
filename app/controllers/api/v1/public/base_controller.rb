module Api
  module V1
    module Public
      # The personal-token JSON API (spec §5): token authentication, the 600-a-minute limit
      # shared with MCP, and the Reader's errors as JSON. Subclasses are one-line wrappers.
      class BaseController < ActionController::API
        # First, so 401 and 429 are covered: the app-wide CSP nonce lives in the session, and a
        # JSON response has no use for a policy; without this every response sets a cookie.
        before_action { request.content_security_policy = nil }

        include Api::PersonalAuthentication
        include Api::RateLimited
        api_rate_limit to: Api::RateLimited::PERSONAL_LIMIT, scope: Api::RateLimited::PERSONAL_SCOPE

        rescue_from(Reader::NotFound, ActiveRecord::RecordNotFound) { render json: { error: "not found" }, status: :not_found }
        rescue_from(Reader::InvalidParams) do |error|
          render json: { error: "invalid parameters", details: error.details }, status: :bad_request
        end

        private

        def reader
          @reader ||= Reader.new(user: Current.user, base_url: request.base_url)
        end

        # Query-string parameters only, with symbol keys; the Reader validates them.
        def api_params
          request.query_parameters.to_h.symbolize_keys
        end
      end
    end
  end
end
