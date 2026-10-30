class InvitationsController < ApplicationController
  before_action :set_organization
  before_action -> { require_role!(:admin) }
  before_action :set_invitation, only: %i[destroy resend]

  # After set_organization and the role check, so only authorised admins are counted.
  rate_limit to: 20, within: 1.hour, only: %i[create resend], by: -> { Current.user.id },
             with: -> { redirect_to members_path, alert: "Too many invitations — try again later." }

  def create
    attrs = invitation_params
    invitation, raw_token = Invitation.issue!(organization: @organization, email: attrs[:email], role: attrs[:role],
                                               invited_by: Current.user)
    return show_link(invitation, raw_token) unless Hideout.mail_enabled?

    InvitationMailer.invite(invitation).deliver_later
    redirect_to members_path, notice: "Invitation sent to #{invitation.email}."
  rescue Invitation::NotIssuable => e
    redirect_to members_path, alert: e.message
  rescue ActiveRecord::RecordInvalid => e
    redirect_to members_path, alert: e.record.errors.full_messages.to_sentence
  end

  def resend
    raw_token = @invitation.reissue!
    return show_link(@invitation, raw_token) unless Hideout.mail_enabled?

    InvitationMailer.invite(@invitation).deliver_later
    redirect_to members_path, notice: "Invitation resent to #{@invitation.email}."
  end

  def destroy
    @invitation.revoke!
    redirect_to members_path, notice: "Invitation to #{@invitation.email} revoked."
  end

  private

  # Without SMTP the admin copies the link (spec 2026-10-29 §6.2). Shown once, never logged or cached.
  def show_link(invitation, raw_token)
    @invitation = invitation
    @accept_url = invitation_acceptance_url(token: raw_token)
    response.headers["Cache-Control"] = "no-store"
    render :link
  end

  # Nested under organizations, so authorization follows the organization.
  def authorization_organization
    current_organization
  end

  def set_organization
    @organization = current_organization
  end

  # Only unaccepted, unrevoked invitations of this organization; anything else is a 404.
  def set_invitation
    @invitation = @organization.invitations.outstanding.find(params[:id])
  end

  # Only email and role are accepted: organization, inviter and token digest are server-side.
  def invitation_params
    params.expect(invitation: %i[email role])
  end

  def members_path
    organization_memberships_path(@organization)
  end
end
