require "rails_helper"

RSpec.describe "MCP tools", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-25 12:00:00") }
  let(:user) { create(:user) }
  let!(:project) { create(:project, owner: user, name: "Demo") }
  let(:plain) { PersonalToken.issue!(user: user, name: "claude", expires_in_days: 90).last }
  let(:slug) { project.slug }
  let(:login) { create(:test_case, project: project, full_name: "Login works", file_path: "spec/login_spec.rb", line_number: 3) }

  around { |example| travel_to(now) { example.run } }

  def call_tool(name, **arguments)
    post "/mcp", params: JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: name, arguments: arguments }),
                 headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                            "MCP-Protocol-Version" => "2025-06-18", "Authorization" => "Bearer #{plain}" }
    expect(response).to have_http_status(:ok)
    result = response.parsed_body["result"]
    [ result, result["content"].map { |part| part["text"] } ]
  end

  def rest(path, **params)
    get path, params: params, headers: { "Authorization" => "Bearer #{plain}" }
    expect_documented_response
    response.parsed_body
  end

  def seed
    baseline = create(:build, project: project, branch: "main", created_at: 2.days.ago)
    create(:test_result, run: create(:run, project: project, build: baseline, flakiness_analyzed_at: 2.days.ago),
                         test_case: login, status: "passed")
    build = create(:build, project: project, branch: "main", status: "failed", total_count: 4, passed_count: 3, failed_count: 1,
                           created_at: 1.hour.ago)
    run = create(:run, project: project, build: build, branch: "main", created_at: 1.hour.ago, flakiness_analyzed_at: now)
    group = create(:error_group, project: project, exception_class: "RuntimeError", sample_message: "boom")
    create(:test_result, run: run, test_case: login, status: "failed", failure_message: "boom", error_group: group)
    3.times { create(:test_result, run: run, status: "passed") }
    build.update_columns(baseline_build_id: baseline.id, baseline_assigned_at: now, gate_status: "failed", gate_evaluated_at: now,
                         gate_result: JSON.generate("rules" => { "pass_rate" => { "min" => 98, "actual" => 75, "outcome" => "failed" } }))
    create(:test_case_verdict, test_case: login, branch: "main", flaky: true, flip_rate: 0.4, flaky_reason: "flips")
    Quarantine.quarantine!(test_case: login, user: user, reason: "Known flaky", days: 14)
    { build: build, group: group }
  end

  it "lists the ten tools in order" do
    post "/mcp", params: JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list"),
                 headers: { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream",
                            "Authorization" => "Bearer #{plain}" }
    expect(response.parsed_body["result"]["tools"].map { |tool| tool["name"] }).to eq(
      %w[list_projects project_health list_builds get_build search_tests get_test list_error_groups get_error_group
         list_flaky_tests list_quarantines]
    )
  end

  it "returns, for every tool, the REST JSON for the same data, as text and as structured content" do
    records = seed
    build = records[:build]
    group = records[:group]

    {
      [ "list_projects", {} ] => [ api_v1_projects_path, { per_page: 100 } ],
      [ "project_health", { project: slug } ] => [ api_v1_project_path(slug), {} ],
      [ "list_builds", { project: slug, branch: "main", status: "failed", since: "7d", page: 1, per_page: 10 } ] =>
        [ api_v1_project_builds_path(slug), { branch: "main", status: "failed", since: "7d", page: 1, per_page: 10 } ],
      [ "get_build", { project: slug, build_id: build.id } ] => [ api_v1_project_build_path(slug, build.id), {} ],
      [ "get_build", { project: slug, build_id: "latest", branch: "main" } ] => [ api_v1_project_build_path(slug, "latest"), { branch: "main" } ],
      [ "search_tests", { project: slug, query: "status:failed" } ] => [ api_v1_project_tests_path(slug), { q: "status:failed" } ],
      [ "get_test", { project: slug, test_id: login.id } ] => [ api_v1_project_test_path(slug, login.id), {} ],
      [ "list_error_groups", { project: slug, since: "7d" } ] => [ api_v1_project_errors_path(slug), { since: "7d" } ],
      [ "get_error_group", { project: slug, error_group_id: group.id } ] => [ api_v1_project_error_path(slug, group.id), {} ],
      [ "list_flaky_tests", { project: slug, branch: "main" } ] => [ api_v1_project_flaky_path(slug), { branch: "main" } ],
      [ "list_quarantines", { project: slug } ] => [ api_v1_project_quarantines_path(slug), { per_page: 100 } ]
    }.each do |(tool, arguments), (path, params)|
      result, (summary, json) = call_tool(tool, **arguments)
      expect(result["isError"]).to be(false), "#{tool}: #{summary}"
      expect(summary.length).to be_between(1, 2_000)
      expect(JSON.parse(json)).to eq(rest(path, **params)), "#{tool} drifted from #{path}"
      expect(result["structuredContent"]).to eq(JSON.parse(json))
      expect(JSON.parse(json).fetch("data", [ :one ])).not_to be_empty, "#{tool} compared an empty list"
    end
  end

  it "summarizes a build with its gate and new failures" do
    build = seed[:build]
    _, (summary, _) = call_tool("get_build", project: slug, build_id: "latest")
    expect(summary).to eq("Build ##{build.id} on main: failed, 75% (3/4), gate failed — pass rate 75% < 98%; " \
                          "1 new failure vs main: Login works")
  end

  it "passes Explore notices through search_tests as data, not as an error (Review Focus 4)" do
    seed
    result, (summary, json) = call_tool("search_tests", project: slug, query: "status:failed foo:bar")

    expect(result["isError"]).to be(false)
    expect(JSON.parse(json)["meta"]).to include("query" => "status:failed", "notices" => [ %(Ignored "foo:bar": unknown filter) ])
    expect(summary).to eq(%(1 test matches "status:failed". Notices: Ignored "foo:bar": unknown filter. Tests: Login works (failed, 1 failure)))
  end

  it "answers a missing build, record or bad argument with isError (Review Focus 3)" do
    create(:build, project: project, branch: "main")
    {
      [ "get_build", { project: slug, build_id: "latest", branch: "release" } ] => "No builds on branch 'release' in project '#{slug}'.",
      [ "get_build", { project: slug, build_id: "newest" } ] => %(Invalid arguments: build_id must be an integer or "latest"),
      [ "get_build", { project: slug, build_id: 999_999 } ] => "No build 999999 in project '#{slug}'.",
      [ "get_test", { project: slug, test_id: 999_999 } ] => "No test 999999 in project '#{slug}'.",
      [ "get_error_group", { project: slug, error_group_id: 999_999 } ] => "No error group 999999 in project '#{slug}'.",
      [ "list_builds", { project: "nope" } ] => "No project 'nope'. Call list_projects for the slugs you can see."
    }.each do |(tool, arguments), message|
      result, texts = call_tool(tool, **arguments)
      expect(result["isError"]).to be(true), tool
      expect(texts).to eq([ message ])
    end

    result, texts = call_tool("list_builds", project: slug, status: "green")
    expect(result["isError"]).to be(true)
    expect(texts.first).to start_with("Invalid arguments")
  end

  it "keeps all text within 50,000 characters and tells how to reach the cut items" do
    50.times { |i| create(:build, project: project, commit_message: "c" * 2_000, created_at: i.minutes.ago) }

    _, (summary, json) = call_tool("list_builds", project: slug)

    expect(summary.length + json.length).to be <= 50_000
    shown = JSON.parse(json)["data"].size
    expect(shown).to be < 50
    expect(summary).to end_with("showing #{shown} of 50; page cut to fit, pass a smaller per_page")

    _, (small_summary, small_json) = call_tool("list_builds", project: slug, per_page: shown)
    expect(JSON.parse(small_json)["data"].size).to eq(shown)
    expect(small_summary).not_to include("page cut to fit")
  end

  it "keeps the Explore notices in the summary when a long test list is cut at 2,000 characters (I1)" do
    run = create(:run, project: project, build: create(:build, project: project, branch: "main"), branch: "main", created_at: 1.hour.ago)
    50.times do |i|
      test_case = create(:test_case, project: project, full_name: "Checkout flow #{i} #{'very long scenario name ' * 3}")
      create(:test_result, run: run, test_case: test_case, status: "failed", failure_message: "boom")
    end

    _, (summary, json) = call_tool("search_tests", project: slug, query: "Checkout foo:bar", per_page: 100)

    expect(summary.length).to be <= 2_000
    expect(summary).to include('Notices: Ignored "foo:bar": unknown filter')
    expect(summary).to end_with("...")
    expect(JSON.parse(json)["meta"]["notices"]).to eq([ %(Ignored "foo:bar": unknown filter) ])
  end

  it "takes an optional per_page on the four paged tools, with the REST validation and messages" do
    seed
    %w[list_builds search_tests list_error_groups list_flaky_tests].each do |tool|
      result, (_, json) = call_tool(tool, project: slug, per_page: 1)
      expect(result["isError"]).to be(false), tool
      expect(JSON.parse(json)["meta"]["per_page"]).to eq(1), tool
    end

    [ 0, 101 ].each do |bad|
      result, texts = call_tool("list_builds", project: slug, per_page: bad)
      expect(result["isError"]).to be(true)
      expect(texts.first).to include("per_page must be an integer from 1 to 100")
    end
  end
end
