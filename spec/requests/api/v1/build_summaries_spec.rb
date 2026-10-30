require "rails_helper"

RSpec.describe "GET /api/v1/builds/summary", type: :request do
  let(:project) { create(:project) }
  let!(:plaintext) { ApiToken.issue!(project: project, name: "CI").last }
  let(:headers) { { "Authorization" => "Bearer #{plaintext}" } }
  let!(:build) { create(:build, project: project, build_key: "gh:1", status: "passed", total_count: 3, passed_count: 3) }

  it "returns state, markdown and url" do
    get "/api/v1/builds/summary", params: { build_key: "gh:1" }, headers: headers
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.keys).to eq(%w[state markdown url gate])
    expect(body["gate"]).to eq("pending")
    expect(body["state"]).to eq("passed")
    expect(body["url"]).to eq("http://www.example.com/projects/#{project.slug}/builds/#{build.id}")
    expect(body["markdown"].lines.first.chomp).to eq("<!-- raider-reporter:build-comment -->")
    expect(body["markdown"]).to include("[View build](#{body['url']})")
  end

  it "returns the gate verdict" do
    build.update_columns(gate_status: "failed", gate_result: '{"rules":{}}', gate_evaluated_at: Time.current)
    get "/api/v1/builds/summary", params: { build_key: "gh:1" }, headers: headers
    expect(response.parsed_body["gate"]).to eq("failed")
  end

  it "returns the same Markdown structure for an Azure build" do
    azure = create(:build, project: project, build_key: "azure_pipelines:x:1:1", provider: "azure_pipelines", status: "passed",
                           total_count: 3, passed_count: 3, pr_url: "https://dev.azure.com/o/P/_git/r/pullrequest/7")
    get "/api/v1/builds/summary", params: { build_key: azure.build_key }, headers: headers
    expect(response).to have_http_status(:ok)
    azure_markdown = response.parsed_body["markdown"]
    get "/api/v1/builds/summary", params: { build_key: "gh:1" }, headers: headers
    normalize = ->(markdown) { markdown.lines.map { |line| line.gsub(/\d+/, "N") } }
    expect(normalize.call(azure_markdown)).to eq(normalize.call(response.parsed_body["markdown"]))
  end

  it "returns 404 for another project's build_key" do
    other = create(:build, build_key: "gh:other")
    get "/api/v1/builds/summary", params: { build_key: other.build_key }, headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "not found")
  end

  it "returns 404 for an unknown or missing build_key" do
    get "/api/v1/builds/summary", params: { build_key: "nope" }, headers: headers
    expect(response).to have_http_status(:not_found)
    get "/api/v1/builds/summary", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "returns 401 without a token" do
    get "/api/v1/builds/summary", params: { build_key: "gh:1" }
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end

  it "returns 401 with a bad token" do
    get "/api/v1/builds/summary", params: { build_key: "gh:1" }, headers: { "Authorization" => "Bearer nope" }
    expect(response).to have_http_status(:unauthorized)
  end
end
