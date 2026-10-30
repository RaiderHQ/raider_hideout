module Api
  # Bearer authentication with a personal (rdp_) token (spec §4.3). Sets Current.user for this
  # request only (no session, no cookie) and @personal_token for the rate limit and the logs.
  # Project (rdr_) tokens fail here, as rdp_ tokens fail Api::TokenAuthentication.
  module PersonalAuthentication
    extend ActiveSupport::Concern

    included do
      before_action :authenticate_personal_token
    end

    private

    def authenticate_personal_token
      plaintext = request.authorization.to_s[/\ABearer\s+(\S+)\s*\z/i, 1]
      @personal_token = PersonalToken.authenticate(plaintext)
      return render(json: { error: "unauthorized" }, status: :unauthorized) unless @personal_token

      Current.user = @personal_token.user
    end
  end
end
