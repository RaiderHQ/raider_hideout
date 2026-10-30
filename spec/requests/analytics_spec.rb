require "rails_helper"

RSpec.describe "Analytics", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-28 12:00:00") }
  let(:owner) { create(:user) }
  let(:organization) { create(:organization).tap { create(:membership, organization: _1, user: owner, role: "owner") } }
  let(:project) { create(:project, organization: organization, name: "Shop") }
  let(:login) { create(:test_case, project: project, full_name: "Login works", file_path: "spec/login_spec.rb") }
  let(:cart) { create(:test_case, project: project, full_name: "Cart totals", file_path: "spec/cart_spec.rb") }

  around { |example| travel_to(now) { example.run } }

  def member(role)
    create(:user).tap { create(:membership, organization: organization, user: _1, role: role) }
  end

  def seed
    build = analytics_build(project: project, at: 2.days.ago, passed_count: 9, failed_count: 1, duration_ms: 4_000, flaky_count: 1)
    analytics_result(build: build, test_case: login, status: "failed", duration: 1_500, tags: [ "smoke" ])
    analytics_result(build: build, test_case: login, status: "passed", duration: 500, tags: [ "smoke" ])
    analytics_result(build: build, test_case: cart, status: "passed", duration: 50)
    create(:test_case_verdict, test_case: login, branch: "main", flaky: true, flip_rate: 0.4, flaky_reason: "flips")
  end

  describe "GET /projects/:project_id/analytics" do
    before { seed }

    %w[viewer admin].each do |role|
      it "shows the headline, the four lists and the three charts to a #{role}" do
        sign_in(member(role))
        get project_analytics_path(project)

        expect(response).to have_http_status(:ok)
        body = response.body
        page = Nokogiri::HTML(body)
        section = ->(testid) { page.at_css(%([data-testid="#{testid}"])).text }
        expect(body).to include("Shop", "main · last 30 days", "Most failing", "Flakiest", "Spec files", "Login works", "Cart totals", "spec/login_spec.rb")
        expect(section["analytics-headline"]).to include("Builds", "Pass rate", "Average build duration", "Flaky tests", "90%", "4.0s")
        expect(section["analytics-slowest"]).to include("Slowest", "Login works", "Cart totals")
        expect(section["analytics-flaky"]).to include("Flakiest", "Login works")
        expect(body).to include("Status flips often between runs", "40%", "1.0s", "50 ms")
        expect(body).to include('id="failure-rate-chart"', 'id="duration-chart"', 'id="flaky-chart"')
        expect(body).not_to include(AnalyticsHelper::BUILD_NOTE)
      end
    end

    it "offers Quarantine on a flaky test to members, not viewers" do
      sign_in(member("viewer"))
      get project_analytics_path(project)
      expect(response.body).not_to include(project_test_case_path(project, login, branch: "main", anchor: "quarantine"))

      sign_in(member("member"))
      get project_analytics_path(project)
      expect(response.body).to include(project_test_case_path(project, login, branch: "main", anchor: "quarantine"))

      create(:quarantine, test_case: login)
      get project_analytics_path(project)
      expect(response.body).not_to include(project_test_case_path(project, login, branch: "main", anchor: "quarantine"))
    end

    it "shows the notices, keeps the canonical query and carries it into the links" do
      sign_in(owner)
      get project_analytics_path(project, q: "status:failed since:24h tag:Smoke")

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include("Ignored &quot;status:failed&quot;: not an analytics filter",
                              "Ignored &quot;since:24h&quot;: use 7d, 30d or 90d")
      expect(body).to include('value="tag:smoke"', AnalyticsHelper::BUILD_NOTE)
      expect(body).not_to include("Cart totals")
      expect(body).to include(CGI.escapeHTML(project_analytics_path(project, format: :csv, list: "failing", q: "tag:smoke")))
      expect(body).to include(CGI.escapeHTML(project_explore_path(project, q: "tag:smoke since:30d sort:failures")))
      expect(body).to include(CGI.escapeHTML(project_explore_path(project, q: "tag:smoke since:30d sort:duration")))
      expect(body).to include(CGI.escapeHTML(project_explore_path(project, q: "tag:smoke is:flaky since:30d")))
      expect(body).to include(CGI.escapeHTML(project_analytics_path(project, q: "file:spec/login_spec.rb tag:smoke")))
    end

    it "narrows the lists to a spec file" do
      sign_in(owner)
      get project_analytics_path(project, q: "file:spec/cart_spec.rb")
      expect(response.body).to include("Cart totals")
      expect(response.body).not_to include("Login works")
    end

    it "says when a list has nothing for the filter" do
      sign_in(owner)
      get project_analytics_path(project, q: "tag:nothing")
      # Four lists and the failure-rate chart; the duration and flaky charts keep their build series.
      expect(response.body.scan("Nothing to show for this filter.").size).to eq(5)
      expect(response.body).to include('id="duration-chart"', 'id="flaky-chart"')
    end

    it "has no inline handlers or inline styles" do
      sign_in(owner)
      get project_analytics_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to match(/\son[a-z]+\s*=/i)
      expect(response.body).not_to match(/\sstyle\s*=/i)
    end
  end

  describe "GET /projects/:project_id/analytics.csv" do
    before { seed }

    def csv(list, query = nil, user: member("viewer"))
      sign_in(user)
      get project_analytics_path(project, format: :csv, list: list, q: query)
      CSV.parse(response.body)
    end

    it "sends a list to a viewer as an attachment that is never stored" do
      rows = csv("failing")

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to start_with(%(attachment; filename="#{project.slug}-failing-2026-10-28.csv"))
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(rows).to eq([
        %w[test_id test file failures executed failure_rate last_failure flaky quarantined url],
        [ login.id.to_s, "Login works", "spec/login_spec.rb", "1", "2", "50", "2026-10-26T12:00:00Z", "true", "false",
          "http://www.example.com#{project_test_case_path(project, login, branch: 'main')}" ]
      ])
    end

    it "sends every list in the page's order and columns, following the filter" do
      expect(csv("slowest").map { _1.first(4) }).to eq([
        %w[test_id test file avg_duration_ms], [ login.id.to_s, "Login works", "spec/login_spec.rb", "1000" ],
        [ cart.id.to_s, "Cart totals", "spec/cart_spec.rb", "50" ]
      ])
      expect(csv("flaky")).to eq([
        %w[test_id test file flip_rate reason flaky_since_build samples quarantined url],
        [ login.id.to_s, "Login works", "spec/login_spec.rb", "40", "flips", nil, Flakiness::Analyzer::MIN_SAMPLES.to_s, "false",
          "http://www.example.com#{project_test_case_path(project, login, branch: 'main')}" ]
      ])
      expect(csv("files")).to eq([
        %w[file tests executed failures failure_rate total_duration_ms],
        %w[spec/login_spec.rb 1 2 1 50 2000], %w[spec/cart_spec.rb 1 1 0 0 50]
      ])
      expect(csv("files", "file:cart").drop(1)).to eq([ %w[spec/cart_spec.rb 1 1 0 0 50] ])
      expect(csv("trend", "since:7d").find { _1.first == "2026-10-26" }).to eq(%w[2026-10-26 3 1 33 683 4000 1])
    end

    it "guards formula cells in the download" do
      evil = create(:test_case, project: project, full_name: "=cmd|' /C calc'!A0", file_path: "-spec/evil_spec.rb")
      search_result(evil, status: "failed", at: 1.day.ago)

      row = csv("failing").find { _1.first == evil.id.to_s }
      expect(row[1..2]).to eq([ "'=cmd|' /C calc'!A0", "'-spec/evil_spec.rb" ])
    end

    it "caps a list at 5,000 rows" do
      run = create(:run, project: project, branch: "main", created_at: 1.day.ago)
      ids = TestCase.insert_all!(Array.new(5_001) { |i| { project_id: project.id, full_name: format("Bulk %04d", i), file_path: "spec/bulk_spec.rb", test_key: "bulk-#{i}" } },
                                 returning: [ :id ]).rows.flatten
      TestResult.insert_all!(ids.map { |id| { run_id: run.id, test_case_id: id, identifier: "bulk-#{id}", status: "failed" } })

      rows = csv("failing")

      expect(rows.size).to eq(1 + Analytics::Csv::LIMIT)
      expect(Analytics::Csv::LIMIT).to eq(5_000)
      expect(rows.second.second).to eq("Bulk 0000")
    end

    it "404s for an unknown or missing list, and for another organization's project" do
      sign_in(owner)
      get project_analytics_path(project, format: :csv, list: "bogus")
      expect(response).to have_http_status(:not_found)
      get project_analytics_path(project, format: :csv)
      expect(response).to have_http_status(:not_found)

      sign_in(create(:user))
      get project_analytics_path(project, format: :csv, list: "failing")
      expect(response).to have_http_status(:not_found)
    end
  end

  it "says there are no builds in every section when the branch had none in the window" do
    analytics_build(project: project, at: 40.days.ago)
    sign_in(owner)
    get project_analytics_path(project, q: "since:7d")

    # The headline, the four lists and the three charts.
    expect(response.body.scan("No builds on main in the last 7 days.").size).to eq(8)
    expect(response.body).not_to include('id="failure-rate-chart"')
  end

  it "shows a blank flip rate on the page for a flaky verdict without one" do
    create(:test_case_verdict, test_case: cart, branch: "main", flaky: true, flip_rate: nil)
    build = analytics_build(project: project, at: 1.day.ago)
    analytics_result(build: build, test_case: cart, status: "passed")
    sign_in(owner)
    get project_analytics_path(project)

    cells = Nokogiri::HTML(response.body).css('[data-testid="analytics-flaky"] tbody tr').map { _1.css("td")[2].text.strip }
    expect(cells).to eq([ "–" ])
  end

  it "keeps the results visible when the only build in the window was created just before it" do
    build = analytics_build(project: project, at: 30.days.ago - 1.minute)
    analytics_result(build: build, test_case: login, status: "failed", at: 29.days.ago)
    sign_in(owner)
    get project_analytics_path(project)

    page = Nokogiri::HTML(response.body)
    expect(page.at_css('[data-testid="analytics-headline"]').text).to include("No builds on main in the last 30 days.")
    expect(page.at_css('[data-testid="analytics-failing"]').text).to include("Login works")
    expect(page.at_css('[data-testid="analytics-flaky"]').text).to include("Nothing to show for this filter.")
    expect(response.body.scan("No builds on main in the last 30 days.").size).to eq(1)
  end

  it "renders the empty page for builds that report no branch (Review Focus 3)" do
    build = analytics_build(project: project, at: 1.day.ago, branch: nil)
    analytics_result(build: build, test_case: login, status: "failed")
    sign_in(owner)

    get project_analytics_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No builds on main in the last 30 days.")

    get project_analytics_path(project, q: "branch:")
    expect(response.body).to include("Ignored &quot;branch:&quot;: empty value", "No builds on main in the last 30 days.")
  end

  it "404s for another organization's project" do
    sign_in(create(:user))
    get project_analytics_path(project)
    expect(response).to have_http_status(:not_found)
  end

  it "is linked from the project page after Explore" do
    sign_in(owner)
    get project_path(project)
    body = response.body
    expect(body).to include(project_analytics_path(project))
    expect(body.index(project_analytics_path(project))).to be > body.index(project_explore_path(project))
  end
end
