require "rails_helper"

RSpec.describe "Personal token authentication", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let!(:project) { create(:project, owner: user) }

  after { travel_back }

  def list(token = nil, raw: nil)
    authorization = raw || (token && "Bearer #{token}")
    get api_v1_projects_path, headers: authorization ? { "Authorization" => authorization } : {}
    expect_documented_response
  end

  def slugs = response.parsed_body["data"].map { |entry| entry["slug"] }

  def expect_unauthorized
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "rejects a missing, malformed or unknown token" do
    list
    expect_unauthorized
    list(raw: "Token abc")
    expect_unauthorized
    list("rdp_#{'x' * 32}")
    expect_unauthorized
  end

  it "rejects an expired token" do
    _, plain = PersonalToken.issue!(user: user, name: "short", expires_in_days: 30)
    travel 31.days
    list(plain)
    expect_unauthorized
  end

  it "rejects a revoked token" do
    token, plain = PersonalToken.issue!(user: user, name: "old", expires_in_days: 90)
    token.revoke!
    list(plain)
    expect_unauthorized
  end

  it "rejects a project (rdr_) token (Review Focus 2)" do
    list(ApiToken.issue!(project: project, name: "CI").last)
    expect_unauthorized
  end

  it "sees exactly the user's projects, records the use and sets no cookie" do
    team = create(:organization)
    create(:membership, organization: team, user: user, role: "viewer")
    shared = create(:project, organization: team)
    create(:project)
    token, plain = PersonalToken.issue!(user: user, name: "laptop", expires_in_days: 90)

    expect { list(plain) }.not_to change(Session, :count)

    expect(response).to have_http_status(:ok)
    expect(slugs).to match_array([ project.slug, shared.slug ])
    expect(slugs).to match_array(user.projects.pluck(:slug))
    expect(token.reload.last_used_at).to be_present
    expect(response.headers["Set-Cookie"]).to be_nil
  end

  it "loses an organization's projects on the next request once the membership is removed (Review Focus 1)" do
    team = create(:organization)
    membership = create(:membership, organization: team, user: user, role: "member")
    team_project = create(:project, organization: team)
    plain = PersonalToken.issue!(user: user, name: "laptop", expires_in_days: 90).last

    list(plain)
    expect(slugs).to include(team_project.slug)

    membership.destroy!
    list(plain)
    expect(slugs).to eq([ project.slug ])
  end

  it "never writes the token to the log" do
    plain = PersonalToken.issue!(user: user, name: "laptop", expires_in_days: 90).last
    log = capture_log { list(plain) }
    expect(log).to include("Api::V1::Public::ProjectsController#index")
    expect(log).not_to include(plain)
  end
end
