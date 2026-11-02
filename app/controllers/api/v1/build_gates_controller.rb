module Api
  module V1
    # A CI build's frozen quality gate verdict, polled by `raider-reporter gate` (spec §4.4).
    class BuildGatesController < ActionController::API
      include Api::TokenAuthentication
      include Api::RateLimited
      api_rate_limit to: 300, only: :show

      def show
        build, requested_attempt = Builds::RunKey.find_build(@api_token.project, params[:build_key])
        return render json: { error: "build not found" }, status: :not_found unless build

        report = build.gate_report
        # The verdict on file is for an earlier attempt: this attempt is still being evaluated.
        awaiting_attempt = requested_attempt > 1 && requested_attempt > build.gate_attempt.to_i
        render json: {
          state: awaiting_attempt ? "pending" : report.state,
          build_state: build.status,
          shards: { received: build.first_attempt_runs.count, expected: build.expected_shards },
          rules: awaiting_attempt ? [] : report.rules.map { |rule| { rule: rule.rule, outcome: rule.outcome, detail: rule.detail } },
          url: project_build_url(build.project, build)
        }
      end
    end
  end
end
