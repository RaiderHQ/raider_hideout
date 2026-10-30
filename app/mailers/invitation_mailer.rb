class InvitationMailer < ApplicationMailer
  # Reads the token when the job runs, so a revoked or resent invite never mails a dead or stale link.
  def invite(invitation)
    return if invitation.token.blank?

    @invitation = invitation
    @organization = invitation.organization
    @inviter = invitation.invited_by.email_address
    @accept_url = invitation_acceptance_url(token: invitation.token)
    subject = "#{@inviter} invited you to #{@organization.name} on Raider Hideout"
    mail(to: invitation.email, subject: subject.gsub(/\s+/, " ").strip)
  end
end
