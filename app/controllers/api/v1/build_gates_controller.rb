module Api
  module V1
    # A CI build's frozen quality gate verdict, polled by `raider-reporter gate` (spec §4.4).
    class BuildGatesController < ActionController::API
      include Api::TokenAuthentication
      include Api::RateLimited
      api_rate_limit to: 300, only: :show

      def show
        build = @api_token.project.builds.find_by(build_key: params[:build_key].to_s)
        return render json: { error: "build not found" }, status: :not_found unless build

        report = build.gate_report
        render json: {
          state: report.state,
          build_state: build.status,
          shards: { received: build.runs.count, expected: build.expected_shards },
          rules: report.rules.map { |rule| { rule: rule.rule, outcome: rule.outcome, detail: rule.detail } },
          url: project_build_url(build.project, build)
        }
      end
    end
  end
end
