require "rails_helper"

RSpec.describe InvitationMailer do
  let(:inviter) { create(:user, email_address: "boss@example.com") }
  let(:organization) { create(:organization, name: "Acme <b>Labs</b>\n  QA") }
  let(:issued) { Invitation.issue!(organization: organization, email: "guest@example.com", role: "viewer", invited_by: inviter) }
  let(:invitation) { issued.first }
  let(:raw_token) { issued.last }
  let(:mail) { described_class.invite(invitation) }

  it "addresses the invitee with a whitespace-collapsed subject" do
    expect(mail.to).to eq([ "guest@example.com" ])
    expect(mail.subject).to eq("boss@example.com invited you to Acme <b>Labs</b> QA on Raider Hideout")
  end

  it "includes the role, expiry and accept URL with the raw token in both parts" do
    url = "http://example.com/invitations/accept?token=#{CGI.escape(raw_token)}"
    expiry = invitation.expires_at.to_date.to_fs(:long)
    [ mail.html_part, mail.text_part ].each do |part|
      body = part.body.to_s
      expect(body).to include("viewer", expiry, url)
    end
  end

  it "sends nothing once the token is gone" do
    invitation.revoke!
    expect { described_class.invite(invitation.reload).deliver_now }.not_to change(ActionMailer::Base.deliveries, :count)
  end

  it "escapes user strings in HTML" do
    html = mail.html_part.body.to_s
    expect(html).to include("Acme &lt;b&gt;Labs&lt;/b&gt;")
    expect(html).not_to include("<b>Labs</b>")
  end

  it "never includes the token digest" do
    expect(mail.body.encoded).not_to include(invitation.token_digest)
  end
end
