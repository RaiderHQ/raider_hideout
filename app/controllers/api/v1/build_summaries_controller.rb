module Api
  module V1
    class BuildSummariesController < ActionController::API
      include Api::TokenAuthentication
      include Api::RateLimited
      api_rate_limit to: 300, only: :show

      def show
        build, = Builds::RunKey.find_build(@api_token.project, params[:build_key])
        return render json: { error: "not found" }, status: :not_found unless build

        url = project_build_url(build.project, build)
        summary = BuildSummary.new(build, url: url)
        render json: { state: summary.state, markdown: summary.markdown, url: url, gate: build.gate_report.state }
      end
    end
  end
end
