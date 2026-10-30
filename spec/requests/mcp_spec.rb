require "rails_helper"

RSpec.describe "POST /mcp", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let!(:project) { create(:project, owner: user, name: "Demo") }
  let(:token_pair) { PersonalToken.issue!(user: user, name: "claude", expires_in_days: 90) }
  let(:plain) { token_pair.last }

  after { travel_back }

  def rpc(method, params = nil, id: 1, token: plain, headers: {})
    body = { jsonrpc: "2.0", method: method }
    body[:id] = id if id
    body[:params] = params if params
    auth = token ? { "Authorization" => "Bearer #{token}" } : {}
    post "/mcp", params: JSON.generate(body),
                 headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                            "MCP-Protocol-Version" => "2025-06-18" }.merge(auth, headers)
    response.body.empty? ? nil : response.parsed_body
  end

  def call_tool(name, arguments = {})
    result = rpc("tools/call", { name: name, arguments: arguments })["result"]
    [ result, result["content"].map { |part| part["text"] } ]
  end

  def rest(path, params = {})
    get path, params: params, headers: { "Authorization" => "Bearer #{plain}" }
    expect_documented_response
    response.parsed_body
  end

  it "answers initialize, notifications/initialized, tools/list and tools/call statelessly" do
    init = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "rspec", version: "1.0" } })
    expect(response).to have_http_status(:ok)
    expect(init["result"]).to include("protocolVersion" => "2025-06-18", "instructions" => RaiderMcp::INSTRUCTIONS)
    expect(init["result"]["serverInfo"]).to include("name" => "raider", "version" => "dev")
    expect(response.headers["Mcp-Session-Id"]).to be_nil

    expect(rpc("notifications/initialized", id: nil)).to be_nil
    expect(response).to have_http_status(:accepted)

    tools = rpc("tools/list", id: 2)["result"]["tools"]
    expect(tools.map { |tool| tool["name"] }).to eq(
      %w[list_projects project_health list_builds get_build search_tests get_test list_error_groups get_error_group
         list_flaky_tests list_quarantines]
    )
    expect(tools.second["inputSchema"]).to include("type" => "object", "required" => [ "project" ])
    expect(tools.map { |tool| tool.dig("annotations", "readOnlyHint") }).to all(be(true))

    result, (summary, json) = call_tool("list_projects")
    expect(response).to have_http_status(:ok)
    expect(result["isError"]).to be(false)
    expect(summary).to eq("1 project: #{project.slug} (Demo): no builds yet")
    expect(JSON.parse(json)).to eq(result["structuredContent"])
  end

  it "returns the REST JSON for list_projects and project_health, with a summary" do
    build = create(:build, project: project, branch: "main", status: "failed", passed_count: 9, failed_count: 1)

    _, (summary, json) = call_tool("list_projects")
    expect(JSON.parse(json)).to eq(rest(api_v1_projects_path, per_page: 100))
    expect(summary).to eq("1 project: #{project.slug} (Demo): latest build ##{build.id} failed 90% on main")

    _, (summary, json) = call_tool("project_health", project: project.slug)
    expect(JSON.parse(json)).to eq(rest(api_v1_project_path(project.slug)))
    expect(summary).to eq("#{project.slug} on main, last 30 days: 1 build, pass rate 90%, 0 flaky, 0 quarantined")
  end

  it "answers an unknown project and a missing argument with isError, never an HTTP error" do
    result, texts = call_tool("project_health", project: "nope")
    expect(response).to have_http_status(:ok)
    expect(result["isError"]).to be(true)
    expect(texts).to eq([ "No project 'nope'. Call list_projects for the slugs you can see." ])

    result, texts = call_tool("project_health")
    expect(response).to have_http_status(:ok)
    expect(result["isError"]).to be(true)
    expect(texts.first).to include("project")
  end

  it "logs an unexpected error with the token id, never the token, and answers Internal error" do
    allow(Api::V1::Public::Reader).to receive(:new).and_raise(RuntimeError, "boom")
    result = texts = nil

    log = capture_log { result, texts = call_tool("list_projects") }

    expect(result["isError"]).to be(true)
    expect(texts).to eq([ "Internal error; try again." ])
    expect(log).to include("MCP tool list_projects failed for personal token #{token_pair.first.id}: RuntimeError: boom")
    expect(log).not_to include(plain)
  end

  it "loses an organization's projects on the next tool call once the membership is removed (Review Focus 1)" do
    team = create(:organization)
    membership = create(:membership, organization: team, user: user, role: "member")
    team_project = create(:project, organization: team, name: "Team")
    slugs = -> { JSON.parse(call_tool("list_projects").last.last)["data"].map { |entry| entry["slug"] } }
    expect(slugs.call).to include(team_project.slug)

    membership.destroy!

    expect(slugs.call).to eq([ project.slug ])
    result, texts = call_tool("project_health", project: team_project.slug)
    expect(result["isError"]).to be(true)
    expect(texts).to eq([ "No project '#{team_project.slug}'. Call list_projects for the slugs you can see." ])
  end

  it "answers 401 for a missing, unknown, revoked or project (rdr_) token (Review Focus 2)" do
    revoked, revoked_plain = PersonalToken.issue!(user: user, name: "old", expires_in_days: 90)
    revoked.revoke!
    [ nil, "rdp_#{'x' * 32}", revoked_plain, ApiToken.issue!(project: project, name: "CI").last ].each do |token|
      expect(rpc("tools/list", token: token)).to eq("error" => "unauthorized")
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "answers 401 for an expired token" do
    expiring = PersonalToken.issue!(user: user, name: "short", expires_in_days: 30).last
    travel 31.days
    expect(rpc("tools/list", token: expiring)).to eq("error" => "unauthorized")
    expect(response).to have_http_status(:unauthorized)
  end

  it "sets no cookie and starts no session, whether it answers 200, 401 or 403" do
    expect do
      rpc("tools/list")
      expect(response).to have_http_status(:ok)
      expect(response.headers["Set-Cookie"]).to be_nil

      rpc("tools/list", token: nil)
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["Set-Cookie"]).to be_nil

      rpc("tools/list", headers: { "Origin" => "https://evil.example" })
      expect(response).to have_http_status(:forbidden)
      expect(response.headers["Set-Cookie"]).to be_nil
    end.not_to change(Session, :count)
  end

  it "answers 403 for an Origin on another host, and allows a same-host Origin or none" do
    expect(rpc("tools/list", headers: { "Origin" => "https://evil.example" })).to eq("error" => "forbidden origin")
    expect(response).to have_http_status(:forbidden)
    rpc("tools/list", headers: { "Origin" => "http://www.example.com" })
    expect(response).to have_http_status(:ok)
    rpc("tools/list")
    expect(response).to have_http_status(:ok)
  end

  it "compares only the Origin's host, so port and scheme variants of localhost pass (Review Focus 5)" do
    host! "localhost"
    {
      "http://localhost:3001" => :ok, "https://localhost" => :ok, "http://LOCALHOST:3000" => :ok,
      "http://127.0.0.1:3001" => :forbidden, "http://localhost.evil.test" => :forbidden, "null" => :forbidden,
      "http://local host" => :forbidden
    }.each do |origin, status|
      rpc("tools/list", headers: { "Origin" => origin })
      expect(response).to have_http_status(status), "Origin #{origin} gave #{response.status}"
    end
  end

  it "compares with APP_HOST in production" do
    allow(Rails.env).to receive(:production?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("APP_HOST").and_return("raider.example")

    rpc("tools/list", headers: { "Origin" => "https://raider.example" })
    expect(response).to have_http_status(:ok)
    rpc("tools/list", headers: { "Origin" => "http://www.example.com" })
    expect(response).to have_http_status(:forbidden)
  end

  it "fails closed in production when APP_HOST is blank: any Origin is forbidden, no Origin is unchanged" do
    allow(Rails.env).to receive(:production?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    [ nil, "" ].each do |blank|
      allow(ENV).to receive(:[]).with("APP_HOST").and_return(blank)

      expect(rpc("tools/list", headers: { "Origin" => "http://www.example.com" })).to eq("error" => "forbidden origin")
      expect(response).to have_http_status(:forbidden)
      rpc("tools/list")
      expect(response).to have_http_status(:ok)
    end
  end

  it "answers 405 to GET and DELETE, before authentication" do
    get "/mcp"
    expect(response).to have_http_status(:method_not_allowed)
    expect(response.headers["Allow"]).to eq("POST")
    expect(response.parsed_body).to eq("error" => "method not allowed")

    delete "/mcp", headers: { "Authorization" => "Bearer #{plain}" }
    expect(response).to have_http_status(:method_not_allowed)
  end
end
