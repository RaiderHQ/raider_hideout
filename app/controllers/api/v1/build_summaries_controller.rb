module Api
  module V1
    class BuildSummariesController < ActionController::API
      include Api::TokenAuthentication
      include Api::RateLimited
      api_rate_limit to: 300, only: :show

      def show
        build = @api_token.project.builds.find_by(build_key: params[:build_key].to_s)
        return render json: { error: "not found" }, status: :not_found unless build

        url = project_build_url(build.project, build)
        summary = BuildSummary.new(build, url: url)
        render json: { state: summary.state, markdown: summary.markdown, url: url, gate: build.gate_report.state }
      end
    end
  end
end
