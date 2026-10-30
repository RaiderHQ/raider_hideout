class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_access
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_registration_path, alert: "Try again later." }
  before_action :set_invitation
  before_action :require_signup_allowed

  def new
    @user = User.new(email_address: @invitation&.email)
  end

  def create
    @user = User.new(params.expect(user: %i[email_address password password_confirmation]))
    if @invitation && @user.email_address != @invitation.email
      @user.errors.add(:base, "Use the invited email address")
      return render(:new, status: :unprocessable_content)
    end

    if register
      if session.delete(:invitation_token)
        session.delete(:return_to_after_authenticating)
        flash[:alert] = "Your invitation is no longer valid" unless @invitation
      end
      start_new_session_for @user
      UserMailer.email_verification(@user).deliver_later unless @user.verified?
      redirect_after_sign_up
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  # Invite-only unless HIDEOUT_OPEN_SIGNUP is on (spec 2026-10-29 §6.1).
  def require_signup_allowed
    raise ActiveRecord::RecordNotFound unless Hideout.open_signup? || @invitation
  end

  # A pending invitation remembered by the invitation page fixes the email.
  def set_invitation
    invitation = Invitation.find_by_token(session[:invitation_token])
    @invitation = invitation if invitation&.pending?
  end

  # Creates the user, the personal organization and (when invited) the
  # membership in one transaction. Retries once on a unique-index race (e.g.
  # two sign-ups picking the same organization slug); never raises.
  def register(attempts: 2)
    ActiveRecord::Base.transaction do
      @user.save or raise ActiveRecord::Rollback
      Organization.create_personal!(@user)
      accept_invitation
      # They reached sign-up through a link sent to this address (ruling R1).
      @user.update_column(:email_verified_at, Time.current) if @invitation
      true
    end
  rescue ActiveRecord::RecordNotUnique
    retry if (attempts -= 1).positive?
    sign_up_failed
  rescue ActiveRecord::RecordInvalid
    sign_up_failed
  end

  # Revoked or resent since the form was rendered: sign up normally instead.
  # accept! raises before writing anything, so the transaction can go on.
  def accept_invitation
    @invitation&.accept!(@user)
  rescue Invitation::NotAcceptable
    @invitation = nil
  end

  def sign_up_failed
    @user.errors.add(:base, "We couldn't create your account. Please try again.") if @user.errors.empty?
    false
  end

  def redirect_after_sign_up
    if @invitation
      organization = @invitation.organization
      redirect_to organization_path(organization), notice: "You joined #{organization.name}"
    else
      redirect_to verify_email_path
    end
  end
end
