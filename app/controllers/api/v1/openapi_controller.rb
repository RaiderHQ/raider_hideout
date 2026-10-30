module Api
  module V1
    # The hand-written OpenAPI 3.1 document (docs/openapi.yaml) as JSON, read once when the
    # class loads (at boot in production). No token, no data.
    class OpenapiController < ActionController::API
      DOCUMENT = JSON.generate(YAML.safe_load_file(Rails.root.join("docs/openapi.yaml"))).freeze

      before_action { request.content_security_policy = nil }

      def show
        render json: DOCUMENT
      end
    end
  end
end
