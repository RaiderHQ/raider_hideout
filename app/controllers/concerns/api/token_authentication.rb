module Api
  # Bearer-token authentication for API controllers; sets @api_token.
  module TokenAuthentication
    extend ActiveSupport::Concern

    included do
      before_action :authenticate_token
    end

    private

    def authenticate_token
      plaintext = request.authorization.to_s[/\ABearer\s+(\S+)\s*\z/i, 1]
      @api_token = ApiToken.authenticate(plaintext)
      render json: { error: "unauthorized" }, status: :unauthorized unless @api_token
    end
  end
end
