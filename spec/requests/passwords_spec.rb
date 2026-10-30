require "rails_helper"

RSpec.describe "Password reset", type: :request do
  let(:user) { create(:user) }
  let(:token) { user.password_reset_token }

  it "has no token in the route path" do
    expect(edit_password_path(token: token)).to start_with("/passwords/edit?token=")
  end

  it "shows the form with the token in a hidden field" do
    get edit_password_path(token: token)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(name="token" id="token" value="#{token}"))
  end

  it "resets the password and drops sessions" do
    sign_in(user)
    patch password_path, params: { token: token, password: "newpass123", password_confirmation: "newpass123" }
    expect(response).to redirect_to(new_session_path)
    expect(user.reload.authenticate("newpass123")).to be_truthy
    expect(user.sessions.count).to eq(0)
  end

  it "redirects back to the form with the token on mismatch" do
    patch password_path, params: { token: token, password: "newpass123", password_confirmation: "nope" }
    expect(response).to redirect_to(edit_password_path(token: token))
  end

  it "rejects an invalid token" do
    get edit_password_path(token: "bogus")
    expect(response).to redirect_to(new_password_path)
  end

  it "mails a link with the token as a query param" do
    mail = PasswordsMailer.reset(user)
    expect(mail.text_part.body.to_s).to include("/passwords/edit?token=")
  end

  it "keeps the raw token out of the request log" do
    log = capture_log do
      get edit_password_path(token: token)
      patch password_path, params: { token: token, password: "a", password_confirmation: "b" }
      follow_redirect!
    end
    expect(log).to include("token=[FILTERED]")
    expect(log).not_to include(token)
  end
  context "without SMTP" do
    before { mail_disabled! }

    it "hides the forgot-password link and page" do
      get new_session_path
      expect(response.body).not_to include("Forgot password?")
      get new_password_path
      expect(response).to have_http_status(:not_found)
      expect { post passwords_path, params: { email_address: "x@example.com" } }.not_to have_enqueued_mail
      expect(response).to have_http_status(:not_found)
    end

    it "still resets a password through a printed link" do
      user = create(:user)
      get edit_password_path(token: user.password_reset_token)
      expect(response).to have_http_status(:ok)
      patch password_path, params: { token: user.password_reset_token, password: "newpass123", password_confirmation: "newpass123" }
      expect(response).to redirect_to(new_session_path)
      expect(User.authenticate_by(email_address: user.email_address, password: "newpass123")).to eq(user)
    end

    it "sends an invalid link to sign-in instead of the hidden page" do
      get edit_password_path(token: "bad")
      expect(response).to redirect_to(new_session_path)
    end
  end
end
