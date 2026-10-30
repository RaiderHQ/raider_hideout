require "rails_helper"

RSpec.describe "Project dashboard", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user, name: "Shop") }

  before { sign_in(user) }

  it "shows stat tiles, trend chart and recent builds" do
    create(:build, project: project, passed_count: 9, failed_count: 1, duration_ms: 4000, commit_message: "First")
    create(:build, project: project, passed_count: 7, failed_count: 3, duration_ms: 6000, commit_message: "Second", status: "failed")
    create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "main", flaky: true)

    get project_path(project)

    body = response.body
    expect(body).to include("80%")          # average of 90 and 70
    expect(body).to include("5.0s")         # average duration
    expect(body).to include("Second", "First", "chart-")
    expect(body).to match(/Flaky.*?1/m)
    expect(body).to match(/Builds.*?2/m)    # build count tile
    expect(body).to include("Pass rate, last 2 builds")
    expect(body).to include('id="builds"')
  end

  it "plots one trend point per build, not per run" do
    build = create(:build, project: project, passed_count: 9, failed_count: 1)
    create(:run, project: project, build: build)
    create(:run, project: project, build: build)
    get project_path(project)
    expect(response.body).to include("Pass rate, last 1 build<").and include("##{build.id}")
  end

  it "loads recent builds once per request" do
    create(:build, project: project)
    queries = []
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:sql].start_with?('SELECT "builds"."default_branch"') # Project#default_branch, not the list

      queries << payload[:sql] if payload[:sql] =~ /FROM "builds"/ && payload[:sql] =~ /LIMIT/ && payload[:name] != "SCHEMA"
    end
    get project_path(project)
    ActiveSupport::Notifications.unsubscribe(sub)
    expect(queries.grep(/ORDER BY/).size).to eq(1)
  end

  it "shows an onboarding hint when there are no builds" do
    get project_path(project)
    expect(response.body).to include("API tokens").and include("No builds yet")
  end

  it "always renders the live builds target so the first broadcast build appears" do
    get project_path(project)
    expect(response.body).to include('id="builds"').and include("No builds yet")
  end

  it "404s on another user's dashboard and hides it from the index" do
    other = create(:project, name: "Elsewhere")
    get project_path(other)
    expect(response).to have_http_status(:not_found)
    get projects_path
    expect(response.body).not_to include("Elsewhere")
  end

  it "shows latest-build status and pass rate on project cards" do
    create(:build, project: project, passed_count: 5, failed_count: 0, status: "passed")
    create(:build, project: project, passed_count: 1, failed_count: 1, status: "failed")
    get projects_path
    expect(response.body).to include("Shop", "failed", "50%")
  end
end
