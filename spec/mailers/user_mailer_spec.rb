require "rails_helper"

RSpec.describe UserMailer do
  it "links to the verification URL" do
    user = create(:user, :unverified)
    mail = described_class.email_verification(user)
    expect(mail.to).to eq([ user.email_address ])
    expect(mail.subject).to eq("Verify your email for Raider Hideout")
    token = CGI.unescape(mail.text_part.body.decoded[%r{/verify_email/confirm\?token=([^\s]+)}, 1])
    expect(User.find_by_token_for(:email_verification, token)).to eq(user)
  end
end
