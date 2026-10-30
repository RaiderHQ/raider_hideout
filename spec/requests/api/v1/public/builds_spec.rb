require "rails_helper"

RSpec.describe "GET /api/v1/projects/:project_slug/builds", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-25 12:00:00") }
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user, name: "Demo") }
  let(:headers) { { "Authorization" => "Bearer #{PersonalToken.issue!(user: user, name: 'laptop', expires_in_days: 90).last}" } }

  around { |example| travel_to(now) { example.run } }

  def builds(slug: project.slug, **params)
    get api_v1_project_builds_path(slug), params: params, headers: headers
    expect_documented_response
    response.parsed_body
  end

  def ids(**params) = builds(**params)["data"].map { |build| build["id"] }

  it "lists builds newest first in the build list shape" do
    older = create(:build, project: project, created_at: 2.hours.ago)
    build = create(:build, project: project, branch: "main", commit_sha: "abc123", commit_message: "Fix login", status: "failed",
                           total_count: 4, passed_count: 3, failed_count: 1, duration_ms: 1200, pr_number: 7,
                           provider: "github_actions", repository: "RaiderHQ/demo", ci_url: "https://ci.example/1",
                           created_at: 1.hour.ago)

    body = builds

    expect(body["data"].map { |entry| entry["id"] }).to eq([ build.id, older.id ])
    expect(body["data"].first).to eq(
      "id" => build.id, "build_key" => build.build_key, "branch" => "main", "commit_sha" => "abc123",
      "commit_message" => "Fix login", "status" => "failed",
      "counts" => { "total" => 4, "passed" => 3, "failed" => 1, "skipped" => 0, "pending" => 0, "flaky" => 0, "quarantined" => 0 },
      "pass_rate" => 75, "gate_status" => "pending", "duration_ms" => 1200,
      "pr" => { "number" => 7, "url" => "https://github.com/RaiderHQ/demo/pull/7" }, "ci_url" => "https://ci.example/1",
      "url" => "http://www.example.com/projects/#{project.slug}/builds/#{build.id}", "created_at" => 1.hour.ago.utc.iso8601
    )
    expect(body["data"].last["pr"]).to be_nil
    expect(body["meta"]).to eq("page" => 1, "per_page" => 50, "total" => 2, "next_page" => nil)
  end

  it "filters by branch, status and since" do
    main_old = create(:build, project: project, branch: "main", status: "passed", created_at: 10.days.ago)
    main_new = create(:build, project: project, branch: "main", status: "failed", created_at: 1.hour.ago)
    feature = create(:build, project: project, branch: "feature/x", status: "incomplete", created_at: 2.hours.ago)

    expect(ids(branch: "main")).to eq([ main_new.id, main_old.id ])
    expect(ids(branch: "feature/x")).to eq([ feature.id ])
    expect(ids(status: "incomplete")).to eq([ feature.id ])
    expect(ids(since: "7d")).to eq([ main_new.id, feature.id ])
    expect(ids(since: "24h", branch: "main", status: "failed")).to eq([ main_new.id ])
    expect(ids(since: "90d").size).to eq(3)
  end

  it "rejects a bad page, status and since with 400 and every detail" do
    get api_v1_project_builds_path(project.slug), params: { status: "green", since: "1y", page: "0" }, headers: headers
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "invalid parameters", "details" => [
      "page must be an integer of at least 1", "status must be one of passed, failed, incomplete",
      "since must be one of 24h, 7d, 30d, 90d"
    ])
    expect_documented_response
  end

  it "rejects a page too large for the database offset with 400" do
    get api_v1_project_builds_path(project.slug), params: { page: "100000000000000000000" }, headers: headers
    expect(response).to have_http_status(:bad_request)
    expect(response.parsed_body).to eq("error" => "invalid parameters", "details" => [ "page must be an integer of at least 1" ])
    expect_documented_response
  end

  it "pages, and returns an empty page past the end" do
    3.times { |i| create(:build, project: project, created_at: i.hours.ago) }
    expect(builds(per_page: 2, page: 2)["data"].size).to eq(1)
    expect(builds(per_page: 2, page: 5)).to eq("data" => [], "meta" => { "page" => 5, "per_page" => 2, "total" => 3, "next_page" => nil })
  end

  it "404s for another organization's project" do
    other = create(:build)
    expect(builds(slug: other.project.slug)).to eq("error" => "not found")
    expect(response).to have_http_status(:not_found)
  end
end
