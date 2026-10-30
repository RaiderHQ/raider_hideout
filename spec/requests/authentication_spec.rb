require "rails_helper"

RSpec.describe "Authentication", type: :request do
  before { open_signup! }

  it "redirects anonymous visitors to sign in" do
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "signs up a new user and signs them in" do
    post registration_path, params: { user: { email_address: "new@example.com", password: "password123",
                                               password_confirmation: "password123" } }
    expect(response).to redirect_to(verify_email_path)
    expect(User.find_by(email_address: "new@example.com")).to be_present
    follow_redirect!
    expect(response).to have_http_status(:ok)
  end

  it "creates a personal organization owned by the new user at sign-up" do
    post registration_path, params: { user: { email_address: "Ana@X.io", password: "password123",
                                               password_confirmation: "password123" } }
    user = User.find_by!(email_address: "ana@x.io")
    org = user.personal_organization
    expect(org).to have_attributes(name: "ana's organization", personal: true)
    expect(user.role_in(org)).to eq("owner")
  end

  it "rolls the user back when the personal organization can't be created" do
    allow(Organization).to receive(:create_personal!).and_raise(ActiveRecord::RecordInvalid)
    post registration_path, params: { user: { email_address: "new@example.com", password: "password123",
                                               password_confirmation: "password123" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("We couldn&#39;t create your account. Please try again.")
    expect(User.count).to eq(0)
    expect(Organization.count).to eq(0)
  end

  it "truncates a long email local part so the personal organization name fits" do
    local = "a" * 120
    post registration_path, params: { user: { email_address: "#{local}@x.io", password: "password123",
                                               password_confirmation: "password123" } }
    expect(response).to redirect_to(verify_email_path)
    name = User.find_by!(email_address: "#{local}@x.io").personal_organization.name
    expect(name.length).to eq(100)
    expect(name).to end_with("'s organization")
  end

  it "retries once when two sign-ups race for the same organization slug" do
    create(:user, email_address: "ana@one.io")
    calls = 0
    allow(Organization).to receive(:create_personal!).and_wrap_original do |original, user|
      calls += 1
      raise ActiveRecord::RecordNotUnique, "slug taken" if calls == 1

      original.call(user)
    end
    post registration_path, params: { user: { email_address: "ana@two.io", password: "password123",
                                               password_confirmation: "password123" } }
    expect(response).to redirect_to(verify_email_path)
    expect(User.find_by!(email_address: "ana@two.io").personal_organization.slug).to eq("ana-s-organization-2")
  end

  it "re-renders with 422 when the slug race repeats" do
    allow(Organization).to receive(:create_personal!).and_raise(ActiveRecord::RecordNotUnique)
    post registration_path, params: { user: { email_address: "new@example.com", password: "password123",
                                               password_confirmation: "password123" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(User.count).to eq(0)
  end

  it "re-renders sign up with errors on mismatch" do
    post registration_path, params: { user: { email_address: "x@example.com", password: "a", password_confirmation: "b" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(User.count).to eq(0)
    expect(Organization.count).to eq(0)
  end

  it "signs in an existing user" do
    user = create(:user)
    sign_in(user)
    expect(response).to redirect_to(root_url)
  end

  it "serves the public sign-in page with the stylesheet" do
    get new_session_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/<link[^>]+rel="stylesheet"[^>]+tailwind/)
  end
end
