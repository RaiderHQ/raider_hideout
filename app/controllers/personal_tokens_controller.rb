# Account → Tokens (spec §4.2): any signed-in user lists, creates and revokes their own
# personal tokens. Another user's token is never found, so it gives 404.
class PersonalTokensController < ApplicationController
  EXPIRY_OPTIONS = [ [ "30 days", "30" ], [ "90 days", "90" ], [ "365 days", "365" ], [ "Never", "never" ] ].freeze

  def index
    @tokens = own_tokens
  end

  def create
    attrs = params.expect(personal_token: %i[name expires_in])
    @expires_in = attrs[:expires_in].to_s
    @token, @plaintext = PersonalToken.issue!(user: Current.user, name: attrs[:name].to_s,
                                              expires_in_days: expiry_days(@expires_in))
    response.headers["Cache-Control"] = "no-store"
    render :create
  rescue ActiveRecord::RecordInvalid => e
    @token = e.record
    @tokens = own_tokens
    render :index, status: :unprocessable_content
  end

  def destroy
    own_tokens.find(params[:id]).revoke!
    redirect_to personal_tokens_path, notice: "Token revoked."
  end

  private

  def own_tokens
    Current.user.personal_tokens.order(created_at: :desc, id: :desc)
  end

  # "never" is no expiry; a value that is not a whole number reaches the model as given and is rejected there.
  def expiry_days(value)
    return nil if value == "never"

    Integer(value, 10, exception: false) || value
  end
end
