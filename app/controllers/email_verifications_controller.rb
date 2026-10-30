class EmailVerificationsController < ApplicationController
  allow_unauthenticated_access only: :update
  allow_unverified_access
  rate_limit to: 3, within: 1.hour, only: :create, by: -> { Current.user.id },
             with: -> { redirect_to verify_email_path, alert: "Too many emails — try again in an hour." }

  def show
    redirect_to root_path if Current.user.verified?
  end

  def create
    UserMailer.email_verification(Current.user).deliver_later unless Current.user.verified?
    redirect_to verify_email_path, notice: "Sent — check your inbox"
  end

  def update
    user = User.find_by_token_for(:email_verification, params[:token])
    if user
      user.verify_email!
      drop_other_sessions(user)
      if !authenticated?
        redirect_to new_session_path, notice: "Email verified — sign in to continue"
      elsif Current.user == user
        redirect_to(session.delete(:return_to_after_verification) || root_path, notice: "Email verified")
      else
        redirect_to root_path, notice: "Email verified for #{user.email_address}"
      end
    else
      redirect_to(authenticated? ? verify_email_path : new_session_path,
                  alert: "That link has expired or is invalid — send a new one")
    end
  end

  private

  # Closes pre-hijacking: sessions opened before the real owner proved the
  # address (e.g. by an attacker who signed up with it) must not survive.
  def drop_other_sessions(user)
    keep = Current.session if authenticated? && Current.user == user
    user.sessions.where.not(id: keep&.id).destroy_all
    return if keep

    ActionCable.server.remote_connections.where(current_user: user).disconnect(reconnect: true)
  end
end
