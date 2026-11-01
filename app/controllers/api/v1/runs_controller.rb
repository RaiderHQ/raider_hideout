module Api
  module V1
    class RunsController < ActionController::API
      MAX_REQUEST_BYTES = 50.megabytes

      include Api::TokenAuthentication
      include Api::RateLimited
      api_rate_limit to: 120, only: :create

      before_action :reject_oversized_request

      def create
        result = Ingest.call(project: @api_token.project, payload: params.require(:payload), files: attachment_parts)
        run = result.run
        render json: { run_id: run.id, url: project_run_url(run.project, run),
                       build: { id: run.build_id, url: project_build_url(run.project, run.build_id) } },
               status: result.created ? :created : :ok
      rescue ActionController::ParameterMissing
        render json: { error: "invalid payload", details: [ "payload part is required" ] }, status: :unprocessable_content
      rescue Ingest::Invalid => e
        render json: { error: "invalid payload", details: e.details }, status: :unprocessable_content
      end

      private

      def reject_oversized_request
        payload_too_large if request.content_length.to_i > MAX_REQUEST_BYTES
      end

      def payload_too_large
        render json: { error: "payload too large" }, status: 413
      end

      def attachment_parts
        params.to_unsafe_h.select { |key, value| key.start_with?("att_") && value.respond_to?(:original_filename) }
      end
    end
  end
end
