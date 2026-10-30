module Api
  # One per-minute rate limit for every API controller (spec §4.4). CI controllers keep their
  # own buckets (the scope defaults to the controller path); the personal API and MCP pass
  # PERSONAL_SCOPE so one personal token has one 600-a-minute bucket across both.
  module RateLimited
    extend ActiveSupport::Concern

    PERSONAL_LIMIT = 600
    PERSONAL_SCOPE = "personal_api".freeze

    class_methods do
      def api_rate_limit(to:, only: nil, scope: nil)
        rate_limit to: to, within: 1.minute, by: -> { rate_limit_key }, scope: scope,
                   with: -> { response.set_header("Retry-After", "60"); render json: { error: "rate limited" }, status: :too_many_requests },
                   **{ only: only }.compact
      end
    end

    private

    def rate_limit_key
      @personal_token ? "pt:#{@personal_token.id}" : @api_token&.id
    end
  end
end
