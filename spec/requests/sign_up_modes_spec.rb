require "rails_helper"

RSpec.describe "Sign-up modes", type: :request do
  let(:user_params) { { user: { email_address: "new@example.com", password: "password123", password_confirmation: "password123" } } }

  context "by default (invite-only)" do
    it "has no sign-up page and no sign-up link" do
      get new_registration_path
      expect(response).to have_http_status(:not_found)
      post registration_path, params: user_params
      expect(response).to have_http_status(:not_found)
      expect(User.exists?(email_address: "new@example.com")).to be(false)
      get new_session_path
      expect(response.body).not_to include("Create an account")
    end

    it "still lets an invited person sign up" do
      org = create(:organization)
      admin = create(:user)
      create(:membership, organization: org, user: admin, role: "admin")
      _invitation, token = Invitation.issue!(organization: org, email: "new@example.com", role: "member", invited_by: admin)
      get invitation_acceptance_path(token: token)
      get new_registration_path
      expect(response).to have_http_status(:ok)
      post registration_path, params: user_params
      expect(User.find_by!(email_address: "new@example.com").organizations).to include(org)
    end
  end

  context "with HIDEOUT_OPEN_SIGNUP=true" do
    before { open_signup! }

    it "opens sign-up and shows the link" do
      get new_registration_path
      expect(response).to have_http_status(:ok)
      get new_session_path
      expect(response.body).to include("Create an account")
    end
  end
end
