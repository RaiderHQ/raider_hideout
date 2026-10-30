require "rails_helper"

RSpec.describe "Rate limits", type: :request do
  before { open_signup! }

  it "limits sign-ups to 10 per 3 minutes per IP" do
    11.times do |i|
      post registration_path, params: { user: { email_address: "u#{i}@example.com", password: "password123",
                                                 password_confirmation: "password123" } }
      delete session_path if i < 10
    end
    expect(flash[:alert]).to eq("Try again later.")
    expect(User.where("email_address LIKE 'u%@example.com'").count).to eq(10)
  end

  it "limits invitations to 20 per hour per user" do
    admin = create(:user)
    sign_in(admin)
    org = admin.organizations.first
    21.times { |i| post organization_invitations_path(org), params: { invitation: { email: "i#{i}@example.com", role: "member" } } }
    expect(flash[:alert]).to eq("Too many invitations — try again later.")
    expect(org.invitations.count).to eq(20)
  end

  describe "API" do
    let(:project) { create(:project) }
    let!(:token_pair) { ApiToken.issue!(project: project, name: "ci") }
    let(:headers) { { "Authorization" => "Bearer #{token_pair.last}" } }

    it "returns 429 JSON with Retry-After after 120 uploads a minute, per token" do
      120.times { post api_v1_runs_path, headers: headers }
      post api_v1_runs_path, headers: headers
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to eq("error" => "rate limited")
      expect(response.headers["Retry-After"]).to eq("60")

      other = ApiToken.issue!(project: project, name: "other").last
      post api_v1_runs_path, headers: { "Authorization" => "Bearer #{other}" }
      expect(response).not_to have_http_status(:too_many_requests)
    end

    it "limits the gate API to 300 a minute, per token" do
      create(:build, project: project, build_key: "gh:gate")
      300.times { get api_v1_builds_gate_path, params: { build_key: "gh:gate" }, headers: headers }
      get api_v1_builds_gate_path, params: { build_key: "gh:gate" }, headers: headers
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to eq("error" => "rate limited")
      expect(response.headers["Retry-After"]).to eq("60")

      other = ApiToken.issue!(project: project, name: "other").last
      get api_v1_builds_gate_path, params: { build_key: "gh:gate" }, headers: { "Authorization" => "Bearer #{other}" }
      expect(response).to have_http_status(:ok)
    end

    it "limits the build summary API to 300 a minute" do
      300.times { get api_v1_builds_summary_path, params: { build_key: "k" }, headers: headers }
      get api_v1_builds_summary_path, params: { build_key: "k" }, headers: headers
      expect(response).to have_http_status(:too_many_requests)
    end

    it "limits the quarantine API to 300 a minute, per token" do
      300.times { get api_v1_quarantine_path, headers: headers }
      get api_v1_quarantine_path, headers: headers
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to eq("error" => "rate limited")
      expect(response.headers["Retry-After"]).to eq("60")

      other = ApiToken.issue!(project: project, name: "other").last
      get api_v1_quarantine_path, headers: { "Authorization" => "Bearer #{other}" }
      expect(response).to have_http_status(:ok)
    end

    it "limits a personal token to 600 requests a minute, per token" do
      auth = { "Authorization" => "Bearer #{PersonalToken.issue!(user: create(:user), name: 'laptop', expires_in_days: 90).last}" }
      600.times { get api_v1_projects_path, headers: auth }
      expect(response).to have_http_status(:ok)

      get api_v1_projects_path, headers: auth
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to eq("error" => "rate limited")
      expect(response.headers["Retry-After"]).to eq("60")
      expect_documented_response

      other = PersonalToken.issue!(user: create(:user), name: "other", expires_in_days: 90).last
      get api_v1_projects_path, headers: { "Authorization" => "Bearer #{other}" }
      expect(response).to have_http_status(:ok)
    end

    it "shares one 600-a-minute bucket between the personal REST API and MCP" do
      plain = PersonalToken.issue!(user: create(:user), name: "claude", expires_in_days: 90).last
      auth = { "Authorization" => "Bearer #{plain}" }
      mcp = auth.merge("Content-Type" => "application/json", "Accept" => "application/json, text/event-stream")
      tools_list = JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list")

      300.times { get api_v1_projects_path, headers: auth }
      300.times { post "/mcp", params: tools_list, headers: mcp }
      expect(response).to have_http_status(:ok)

      post "/mcp", params: tools_list, headers: mcp
      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to eq("error" => "rate limited")
      expect(response.headers["Retry-After"]).to eq("60")
      get api_v1_projects_path, headers: auth
      expect(response).to have_http_status(:too_many_requests)
    end

    it "does not count unauthenticated requests against a token" do
      5.times { post api_v1_runs_path }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
