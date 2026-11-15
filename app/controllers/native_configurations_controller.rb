# Public, user-free path configuration for the Raider app. The app also uses it to check that a
# server is a Hideout new enough for the app (settings.hideout_app_api). No sign-in, no session,
# no browser check: the app fetches it before anyone signs in.
class NativeConfigurationsController < ActionController::Base
  def show
    request.session_options[:skip] = true
    expires_in 5.minutes, public: true
    render json: NativePathConfiguration.as_json(params[:platform])
  end
end
