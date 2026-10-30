require "rails_helper"

# Review Focus 2: a personal (rdp_) token never works on the CI endpoints.
# The CI controllers' unchanged limits are pinned by spec/requests/rate_limits_spec.rb.
RSpec.describe "CI endpoints and personal tokens", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:personal) { PersonalToken.issue!(user: user, name: "laptop", expires_in_days: 90).last }
  let(:headers) { { "Authorization" => "Bearer #{personal}" } }

  before { create(:build, project: project, build_key: "gh:1") }

  it "rejects an rdp_ token on every CI endpoint with 401" do
    post api_v1_runs_path, headers: headers
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")

    get api_v1_builds_summary_path, params: { build_key: "gh:1" }, headers: headers
    expect(response).to have_http_status(:unauthorized)

    get api_v1_builds_gate_path, params: { build_key: "gh:1" }, headers: headers
    expect(response).to have_http_status(:unauthorized)

    get api_v1_quarantine_path, headers: headers
    expect(response).to have_http_status(:unauthorized)

    expect(Run.count).to eq(0)
  end

  it "does not let rdp_ requests eat a CI token's bucket" do
    ci = ApiToken.issue!(project: project, name: "ci").last
    125.times { post api_v1_runs_path, headers: headers }
    post api_v1_runs_path, headers: { "Authorization" => "Bearer #{ci}" }
    expect(response).not_to have_http_status(:too_many_requests)
    expect(response).not_to have_http_status(:unauthorized)
  end
end
