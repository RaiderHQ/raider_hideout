require "rails_helper"

RSpec.describe "GET /api/v1/projects", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{PersonalToken.issue!(user: user, name: 'laptop', expires_in_days: 90).last}" } }

  def projects(params = {})
    get api_v1_projects_path, params: params, headers: headers
    expect_documented_response
    response.parsed_body
  end

  it "lists the user's projects newest build first, then projects without builds by name" do
    team = create(:organization, name: "Acme")
    create(:membership, organization: team, user: user, role: "viewer")
    older = create(:project, owner: user, name: "Older")
    newer = create(:project, organization: team, name: "Newer")
    quiet_b = create(:project, owner: user, name: "Beta quiet")
    quiet_a = create(:project, owner: user, name: "Alpha quiet")
    create(:project, name: "Foreign")
    create(:build, project: older, created_at: 2.days.ago)
    latest = create(:build, project: newer, branch: "main", status: "failed", passed_count: 9, failed_count: 1,
                            default_branch: "main", created_at: 1.hour.ago)

    body = projects

    expect(body["data"].map { |entry| entry["slug"] }).to eq([ newer.slug, older.slug, quiet_a.slug, quiet_b.slug ])
    expect(body["data"].first).to eq(
      "slug" => newer.slug, "name" => "Newer", "organization" => { "slug" => team.slug, "name" => "Acme" },
      "default_branch" => "main",
      "latest_build" => { "id" => latest.id, "status" => "failed", "pass_rate" => 90, "gate_status" => "pending",
                          "branch" => "main", "created_at" => latest.created_at.utc.iso8601 },
      "url" => "http://www.example.com/projects/#{newer.slug}"
    )
    expect(body["data"].last["latest_build"]).to be_nil
    expect(body["meta"]).to eq("page" => 1, "per_page" => 50, "total" => 4, "next_page" => nil)
  end

  it "pages with page and per_page, and returns an empty page past the end" do
    3.times { |i| create(:project, owner: user, name: "Project #{i}") }

    expect(projects(per_page: 2)["meta"]).to eq("page" => 1, "per_page" => 2, "total" => 3, "next_page" => 2)
    second = projects(per_page: 2, page: 2)
    expect(second["data"].size).to eq(1)
    expect(second["meta"]["next_page"]).to be_nil
    expect(projects(per_page: 2, page: 9)).to eq("data" => [], "meta" => { "page" => 9, "per_page" => 2, "total" => 3, "next_page" => nil })
    expect(projects(per_page: 100)["meta"]["per_page"]).to eq(100)
  end

  it "rejects bad paging with 400 and one detail per parameter" do
    {
      { page: 0 } => [ "page must be an integer of at least 1" ],
      { page: "two" } => [ "page must be an integer of at least 1" ],
      { per_page: 0 } => [ "per_page must be an integer from 1 to 100" ],
      { per_page: 101 } => [ "per_page must be an integer from 1 to 100" ],
      { page: -1, per_page: "x" } => [ "page must be an integer of at least 1", "per_page must be an integer from 1 to 100" ]
    }.each do |params, details|
      get api_v1_projects_path, params: params, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body).to eq("error" => "invalid parameters", "details" => details)
      expect_documented_response
    end
  end

  describe "GET /api/v1/projects/:project_slug" do
    include ActiveSupport::Testing::TimeHelpers

    let(:now) { Time.zone.parse("2026-10-25 12:00:00") }
    let(:project) { create(:project, owner: user, name: "Demo") }

    around { |example| travel_to(now) { example.run } }

    def show(slug = project.slug)
      get api_v1_project_path(slug), headers: headers
      expect_documented_response
      response.parsed_body
    end

    it "adds the default branch's health over the last 30 days" do
      create(:build, project: project, branch: "main", passed_count: 1, failed_count: 1, created_at: 40.days.ago)
      failing = create(:build, project: project, branch: "main", status: "failed", passed_count: 9, failed_count: 1,
                               created_at: 3.days.ago)
      green = create(:build, project: project, branch: "main", passed_count: 10, created_at: 1.day.ago)
      create(:build, project: project, branch: "feature/x", failed_count: 5, created_at: 1.hour.ago)
      group = create(:error_group, project: project, exception_class: "Net::ReadTimeout", sample_message: "m" * 400)
      run = create(:run, project: project, build: failing, branch: "main", created_at: 3.days.ago)
      2.times { create(:test_result, run: run, status: "failed", error_group: group) }
      create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "main", flaky: true)
      create(:quarantine, test_case: create(:test_case, project: project))

      body = show

      get api_v1_projects_path, headers: headers
      expect(body.except("health")).to eq(response.parsed_body["data"].find { |entry| entry["slug"] == project.slug })
      health = body["health"]
      expect(health.except("top_error_groups", "recent_builds"))
        .to eq("builds" => 2, "pass_rate" => 95, "flaky_count" => 1, "quarantined_count" => 1)
      expect(health["top_error_groups"]).to eq([
        { "id" => group.id, "exception_class" => "Net::ReadTimeout", "sample_message" => "m" * 300, "affected_tests" => 2 }
      ])
      expect(health["recent_builds"].map { |build| build["id"] }).to eq([ green.id, failing.id ])
    end

    it "reports an empty health for a project without builds" do
      expect(show["health"]).to eq("builds" => 0, "pass_rate" => nil, "flaky_count" => 0, "quarantined_count" => 0,
                                   "top_error_groups" => [], "recent_builds" => [])
    end

    it "404s for another organization's project and for an unknown slug" do
      [ create(:project).slug, "nope" ].each do |slug|
        expect(show(slug)).to eq("error" => "not found")
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
