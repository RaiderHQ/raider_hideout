module Api
  module V1
    # The token project's active quarantines, fetched by raider_reporter at suite start (spec §5.3).
    class QuarantinesController < ActionController::API
      include Api::TokenAuthentication
      include Api::RateLimited
      api_rate_limit to: 300, only: :index

      def index
        rows = @api_token.project.quarantines.active.joins(:test_case).order("test_cases.test_key ASC")
                         .select("quarantines.id, quarantines.expires_at, test_cases.test_key AS test_key")
        render json: { quarantined: rows.map { |row| { test_key: row.test_key, expires_at: row.expires_at.utc.iso8601 } } }
      end
    end
  end
end
