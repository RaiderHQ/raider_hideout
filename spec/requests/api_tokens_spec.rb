require "rails_helper"

RSpec.describe "API tokens", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }

  before { sign_in(user) }

  it "shows the plaintext token once on create" do
    post project_api_tokens_path(project), params: { api_token: { name: "GitHub Actions" } }
    expect(response).to have_http_status(:ok)
    plain = response.body[/rdr_[1-9A-HJ-NP-Za-km-z]{32}/]
    expect(plain).to be_present
    expect(response.body).to include("RAIDER_TOKEN")
    get project_api_tokens_path(project)
    expect(response.body).to include("GitHub Actions")
    expect(response.body).not_to include(plain)
  end

  it "submits the create form without Turbo so the 200 page renders" do
    get project_api_tokens_path(project)
    expect(response.body).to match(/<form[^>]*data-turbo="false"[^>]*action="[^"]*api_tokens"|<form[^>]*action="[^"]*api_tokens"[^>]*data-turbo="false"/)
  end

  it "marks the plaintext page as no-store" do
    post project_api_tokens_path(project), params: { api_token: { name: "CI" } }
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to match(%r{<head>.*<meta name="turbo-cache-control" content="no-cache">.*</head>}m)
  end

  it "revokes a token" do
    token, = ApiToken.issue!(project: project, name: "Old")
    delete project_api_token_path(project, token)
    expect(response).to redirect_to(project_api_tokens_path(project))
    expect(ApiToken.exists?(token.id)).to be(false)
  end

  it "404s when revoking another project's token" do
    other_token, = ApiToken.issue!(project: create(:project), name: "Theirs")
    delete project_api_token_path(project, other_token)
    expect(response).to have_http_status(:not_found)
    expect(ApiToken.exists?(other_token.id)).to be(true)
  end
end
