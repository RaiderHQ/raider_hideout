class UserMailer < ApplicationMailer
  # Only the user is passed (a GlobalID in the job); the token is minted here.
  def email_verification(user)
    @user = user
    @url = verify_email_confirm_url(token: user.generate_token_for(:email_verification))
    mail(to: user.email_address, subject: "Verify your email for Raider Hideout")
  end
end
