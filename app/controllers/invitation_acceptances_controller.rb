class InvitationAcceptancesController < ApplicationController
  allow_unauthenticated_access only: %i[show]
  before_action :set_invitation

  def show
    # Signed in: the session token is only for sign-up, so drop any stale one.
    return session.delete(:invitation_token) if authenticated?

    # Remember the invite for sign-up, and come back here after sign-in.
    session[:invitation_token] = params[:token]
    session[:return_to_after_authenticating] = request.url
    @existing_user = User.exists?(email_address: @invitation.email)
  end

  def create
    return redirect_to(verify_email_path) unless Current.user.verified?

    return render(:show, status: :forbidden) unless @invitation.for?(Current.user)

    @invitation.accept!(Current.user)
    session.delete(:invitation_token)
    session.delete(:return_to_after_authenticating)
    organization = @invitation.organization
    redirect_to organization_path(organization), notice: "You joined #{organization.name}"
  rescue Invitation::NotAcceptable
    render :invalid, status: :not_found
  end

  private

  # Looked up by digest only; anything not pending gets the same 404 page.
  def set_invitation
    @invitation = Invitation.find_by_token(params[:token])
    render :invalid, status: :not_found unless @invitation&.pending?
  end

  # A signed-out POST accept returns to the invitation page, not the POST URL.
  def request_authentication
    session[:return_to_after_authenticating] = invitation_acceptance_url(token: params[:token])
    redirect_to new_session_path
  end
end
