require "rails_helper"

RSpec.describe "Email verification", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  before { open_signup! }

  def sign_up(email = "new@example.com")
    post registration_path, params: { user: { email_address: email, password: "password123",
                                               password_confirmation: "password123" } }
  end

  it "signs a new user in, sends the email with no token in the job arguments, and shows the check-inbox page" do
    expect { sign_up }.to have_enqueued_mail(UserMailer, :email_verification)
    expect(response).to redirect_to(verify_email_path)
    user = User.find_by!(email_address: "new@example.com")
    expect(user).not_to be_verified
    job = ActiveJob::Base.queue_adapter.enqueued_jobs.find { |j| j["job_class"] == "ActionMailer::MailDeliveryJob" }
    expect(job).to be_present
    expect(job.inspect).not_to include(user.generate_token_for(:email_verification)[0, 20])
    follow_redirect!
    expect(response.body).to include("new@example.com")
  end

  it "verifies through the emailed link, and a second click is harmless" do
    sign_up
    user = User.find_by!(email_address: "new@example.com")
    token = user.generate_token_for(:email_verification)
    get verify_email_confirm_path(token: token)
    expect(user.reload).to be_verified
    expect(response).to redirect_to(root_path)
    get verify_email_confirm_path(token: token)
    expect(response).to have_http_status(:redirect)
  end

  it "rejects expired, tampered and address-changed tokens" do
    sign_up
    user = User.find_by!(email_address: "new@example.com")
    token = user.generate_token_for(:email_verification)
    travel 25.hours do
      get verify_email_confirm_path(token: token)
      expect(user.reload).not_to be_verified
    end
    get verify_email_confirm_path(token: "#{token}x")
    expect(user.reload).not_to be_verified
    user.update!(email_address: "changed@example.com")
    get verify_email_confirm_path(token: token)
    expect(user.reload).not_to be_verified
    expect(flash[:alert]).to include("expired or is invalid")
  end

  it "redirects an unverified user from app pages but leaves sign-out and password reset open" do
    user = create(:user, :unverified)
    sign_in(user)
    project = create(:project, organization: user.organizations.first)
    [ root_path, project_path(project), organizations_path, new_project_path ].each do |path|
      get path
      expect(response).to redirect_to(verify_email_path), "expected #{path} to redirect"
    end
    get new_password_path
    expect(response).to have_http_status(:ok)
    delete session_path
    expect(response).not_to redirect_to(verify_email_path)
  end

  it "never redirects a verified user" do
    sign_in(create(:user))
    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "does not run the verification gate on API requests" do
    post "/api/v1/runs", headers: { "Authorization" => "Bearer nope" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "resends from the check-inbox page" do
    sign_in(create(:user, :unverified))
    expect { post verify_email_path }.to have_enqueued_mail(UserMailer, :email_verification)
    expect(response).to redirect_to(verify_email_path)
  end

  it "verifies a sign-up that accepts a pending invitation at once (ruling R1)" do
    inviter = create(:user)
    org = inviter.organizations.first
    invitation, raw = Invitation.issue!(organization: org, email: "invitee@example.com", role: "member", invited_by: inviter)
    get invitation_acceptance_path(token: raw)
    expect { sign_up("invitee@example.com") }.not_to have_enqueued_mail(UserMailer, :email_verification)
    expect(User.find_by!(email_address: "invitee@example.com")).to be_verified
    expect(invitation.reload.accepted_at).to be_present
  end

  it "makes the link single-use" do
    user = create(:user, :unverified)
    token = user.generate_token_for(:email_verification)
    get verify_email_confirm_path(token: token)
    expect(user.reload).to be_verified
    expect(User.find_by_token_for(:email_verification, token)).to be_nil
  end

  it "keeps the token out of the request log" do
    io = StringIO.new
    old = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    user = create(:user, :unverified)
    token = user.generate_token_for(:email_verification)
    get verify_email_confirm_path(token: token)
    Rails.logger = old
    expect(io.string).to include("token=[FILTERED]")
    expect(io.string).not_to include(token)
  ensure
    Rails.logger = old
  end

  it "drops sessions opened before verification when the owner clicks signed out" do
    sign_up
    user = User.find_by!(email_address: "new@example.com")
    expect(user.sessions.count).to eq(1)
    reset!
    get verify_email_confirm_path(token: user.generate_token_for(:email_verification))
    expect(user.reload).to be_verified
    expect(user.sessions.count).to eq(0)
  end

  it "keeps only the current session when the owner verifies while signed in" do
    user = create(:user, :unverified)
    sign_in(user)
    other = user.sessions.create!(user_agent: "x", ip_address: "1.2.3.4")
    get verify_email_confirm_path(token: user.generate_token_for(:email_verification))
    expect(user.sessions.count).to eq(1)
    expect(Session.exists?(other.id)).to be(false)
  end

  it "returns an unverified user to the page they were heading to" do
    user = create(:user, :unverified)
    sign_in(user)
    inviter = create(:user)
    _, raw = Invitation.issue!(organization: inviter.organizations.first, email: user.email_address, role: "member", invited_by: inviter)
    get invitation_acceptance_path(token: raw)
    expect(response).to redirect_to(verify_email_path)
    log = capture_log { get verify_email_confirm_path(token: user.generate_token_for(:email_verification)) }
    expect(log).to include("Redirected to [FILTERED]")
    expect(log).not_to include(raw)
    expect(response).to redirect_to(invitation_acceptance_path(token: raw))
  end

  it "verifies the token's user when a different user is signed in" do
    other = create(:user, :unverified)
    me = create(:user)
    sign_in(me)
    get verify_email_confirm_path(token: other.generate_token_for(:email_verification))
    expect(other.reload).to be_verified
    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("Email verified for #{other.email_address}")
    expect(me.sessions.count).to eq(1)
  end

  describe "cable connections" do
    it "disconnects the user's connections when all sessions are purged" do
      user = create(:user, :unverified)
      connections = double(disconnect: true)
      allow(ActionCable.server.remote_connections).to receive(:where).with(current_user: user).and_return(connections)
      get verify_email_confirm_path(token: user.generate_token_for(:email_verification))
      expect(connections).to have_received(:disconnect).with(reconnect: true)
    end

    it "leaves connections alone when the current session is kept" do
      user = create(:user, :unverified)
      sign_in(user)
      allow(ActionCable.server.remote_connections).to receive(:where)
      get verify_email_confirm_path(token: user.generate_token_for(:email_verification))
      expect(ActionCable.server.remote_connections).not_to have_received(:where)
    end
  end
end
