require "rails_helper"

RSpec.describe "Invitation acceptance", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:org) { create(:organization, name: "Acme") }
  let(:inviter) { create(:user).tap { |u| create(:membership, organization: org, user: u, role: "admin") } }
  let(:email) { "guest@x.io" }
  let(:issued) { Invitation.issue!(organization: org, email: email, role: "viewer", invited_by: inviter) }
  let(:invitation) { issued.first }
  let(:token) { issued.last }
  let(:invalid_copy) { "This invitation is no longer valid. Ask an admin to send a new one." }

  def sign_up(address, extra = {})
    post registration_path, params: { user: { email_address: address, password: "password123",
                                               password_confirmation: "password123" }.merge(extra) }
  end

  it "logs the token as [FILTERED]" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    old = Rails.logger
    Rails.logger = logger
    ActionController::Base.logger = logger
    get invitation_acceptance_path(token: token)
    expect(io.string).to include("token=[FILTERED]").or include('"token" => "[FILTERED]"').or include('"token"=>"[FILTERED]"')
    expect(io.string).not_to include(token)
  ensure
    Rails.logger = old
    ActionController::Base.logger = old
  end

  describe "invalid tokens" do
    it "shows the invalid page with 404 for an unknown token" do
      get invitation_acceptance_path(token: "nope")
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include(invalid_copy)
    end

    it "404s an expired token" do
      token
      travel 8.days do
        get invitation_acceptance_path(token: token)
        expect(response).to have_http_status(:not_found)
        expect(response.body).to include(invalid_copy)
      end
    end

    it "404s a revoked token" do
      invitation.revoke!
      get invitation_acceptance_path(token: token)
      expect(response).to have_http_status(:not_found)
    end

    it "404s a used token" do
      invitation.update!(accepted_at: Time.current)
      get invitation_acceptance_path(token: token)
      expect(response).to have_http_status(:not_found)
    end

    it "404s the digest used as a token" do
      get invitation_acceptance_path(token: invitation.token_digest)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "signed out, existing user" do
    let!(:guest) { create(:user, email_address: email) }

    it "asks them to sign in and returns to the invitation after sign-in (Review Focus 3)" do
      get invitation_acceptance_path(token: token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Sign in as #{email} to accept")
      log = capture_log { sign_in(guest) }
      expect(log).to include("Redirected to [FILTERED]")
      expect(log).not_to include(token)
      expect(response).to redirect_to(invitation_acceptance_url(token: token))
      follow_redirect!
      expect(response.body).to include("Accept invitation")
      post accept_invitation_path, params: { token: token }
      expect(response).to redirect_to(organization_path(org))
      expect(flash[:notice]).to eq("You joined Acme")
      expect(guest.role_in(org)).to eq("viewer")
      expect(invitation.reload.accepted_at).to be_present
    end
  end

  describe "signed out, no user" do
    before { get invitation_acceptance_path(token: token) }

    it "links to sign-up with the email fixed" do
      expect(response.body).to include("Create an account as #{email} to accept")
      get new_registration_path
      field = Nokogiri::HTML(response.body).at_css("input[name='user[email_address]']")
      expect(field["value"]).to eq(email)
      expect(field["readonly"]).to be_present
    end

    it "creates the user, personal organization and membership on matching sign-up" do
      expect { sign_up("Guest@X.io") }.to change(User, :count).by(1).and change(Membership, :count).by(2)
      user = User.find_by!(email_address: email)
      expect(user.personal_organization).to be_present
      expect(user.role_in(user.personal_organization)).to eq("owner")
      expect(user.role_in(org)).to eq("viewer")
      expect(invitation.reload.accepted_at).to be_present
      expect(response).to redirect_to(organization_path(org))
      expect(flash[:notice]).to eq("You joined Acme")
      expect(session[:invitation_token]).to be_nil
    end

    it "rejects a different email and creates nothing" do
      expect { sign_up("other@x.io") }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Use the invited email address")
      expect(Organization.where(personal: true).count).to eq(1) # the inviter's
      expect(invitation.reload.accepted_at).to be_nil
    end
  end

  describe "signed in" do
    it "shows the mismatch copy and 403s accept for the wrong email (Review Focus 3)" do
      other = create(:user, email_address: "other@x.io")
      sign_in(other)
      get invitation_acceptance_path(token: token)
      expect(response.body).to include("This invitation is for #{email}. You are signed in as other@x.io. Sign out and use that account.")
      expect(response.body).not_to include("Accept invitation")
      expect { post accept_invitation_path, params: { token: token } }.not_to change(Membership, :count)
      expect(response).to have_http_status(:forbidden)
      expect(invitation.reload.accepted_at).to be_nil
    end

    it "accepts for the matching email, case-insensitively" do
      guest = create(:user, email_address: email)
      sign_in(guest)
      get invitation_acceptance_path(token: token)
      expect(response.body).to include("Acme", "viewer", "Accept invitation")
      expect { post accept_invitation_path, params: { token: token } }.to change(Membership, :count).by(1)
      expect(guest.role_in(org)).to eq("viewer")
    end

    it "keeps an existing member's role and still marks the invite accepted" do
      guest = create(:user, email_address: email)
      token
      create(:membership, organization: org, user: guest, role: "admin")
      sign_in(guest)
      expect { post accept_invitation_path, params: { token: token } }.not_to change(Membership, :count)
      expect(guest.role_in(org)).to eq("admin")
      expect(invitation.reload.accepted_at).to be_present
    end

    it "can't reuse an accepted invite" do
      guest = create(:user, email_address: email)
      sign_in(guest)
      post accept_invitation_path, params: { token: token }
      org.memberships.find_by!(user: guest).destroy!
      post accept_invitation_path, params: { token: token }
      expect(response).to have_http_status(:not_found)
      expect(guest.role_in(org)).to be_nil
    end

    it "requires sign-in to accept" do
      post accept_invitation_path, params: { token: token }
      expect(response).to redirect_to(new_session_path)
      expect(invitation.reload.accepted_at).to be_nil
    end
  end

  describe "session clean-up" do
    before { open_signup! }

    it "forgets the invitation after an invite sign-up, so the next sign-in goes to the dashboard" do
      get invitation_acceptance_path(token: token)
      sign_up(email)
      expect(session[:return_to_after_authenticating]).to be_nil
      delete session_path
      sign_in(User.find_by!(email_address: email))
      expect(response).to redirect_to(root_url)
    end

    it "forgets the invitation after accepting" do
      guest = create(:user, email_address: email)
      get invitation_acceptance_path(token: token)
      sign_in(guest)
      follow_redirect!
      post accept_invitation_path, params: { token: token }
      expect(session[:invitation_token]).to be_nil
      expect(session[:return_to_after_authenticating]).to be_nil
      delete session_path
      sign_in(guest)
      expect(response).to redirect_to(root_url)
    end

    it "drops the invitation on sign-out, so sign-up is no longer email-locked" do
      get invitation_acceptance_path(token: token)
      sign_in(create(:user, email_address: "other@x.io"))
      delete session_path
      get new_registration_path
      field = Nokogiri::HTML(response.body).at_css("input[name='user[email_address]']")
      expect(field["readonly"]).to be_nil
      expect(field["value"]).to be_blank
    end

    it "drops the session token when an authenticated user opens an invite" do
      get invitation_acceptance_path(token: token)
      expect(session[:invitation_token]).to eq(token)
      sign_in(create(:user, email_address: "other@x.io"))
      get invitation_acceptance_path(token: token)
      expect(session[:invitation_token]).to be_nil
    end

    it "sends a signed-out POST accept back to the invitation page after sign-in" do
      guest = create(:user, email_address: email)
      post accept_invitation_path, params: { token: token }
      expect(response).to redirect_to(new_session_path)
      sign_in(guest)
      expect(response).to redirect_to(invitation_acceptance_url(token: token))
    end
  end

  describe "invitation gone before sign-up" do
    before do
      open_signup!
      get invitation_acceptance_path(token: token)
    end

    it "signs up normally when the invite was revoked" do
      invitation.revoke!
      expect { sign_up(email) }.to change(User, :count).by(1).and change(Membership, :count).by(1)
      user = User.find_by!(email_address: email)
      expect(user.organizations).to eq([ user.personal_organization ])
      expect(response).to redirect_to(verify_email_path)
      expect(flash[:alert]).to eq("Your invitation is no longer valid")
      expect(session[:invitation_token]).to be_nil
    end

    it "signs up normally when the invite was resent (old token)" do
      invitation.reissue!
      sign_up(email)
      expect(User.find_by!(email_address: email).role_in(org)).to be_nil
      expect(flash[:alert]).to eq("Your invitation is no longer valid")
    end

    it "signs up normally when the invite is revoked mid-sign-up" do
      allow_any_instance_of(Invitation).to receive(:accept!).and_raise(Invitation::NotAcceptable)
      expect { sign_up(email) }.to change(User, :count).by(1)
      expect(flash[:alert]).to eq("Your invitation is no longer valid")
    end
  end
end
