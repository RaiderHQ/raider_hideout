require "rails_helper"

RSpec.describe "Errors explorer", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }

  before { sign_in(user) }

  def group(klass = "RuntimeError", message: "boom", frame: "", **attrs)
    create(:error_group, project: project, exception_class: klass, normalized_message: message, frame: frame, **attrs)
  end

  def fail_in(group, count: 1, at: 1.day.ago, branch: "main", build: nil, name: nil, **attrs)
    build ||= create(:build, project: project, branch: branch)
    run = create(:run, project: project, build: build, branch: branch, created_at: at)
    Array.new(count) do |i|
      kase = create(:test_case, project: project, full_name: name || "case #{SecureRandom.hex(3)} #{i}")
      create(:test_result, run: run, test_case: kase, status: "failed", error_group: group, created_at: at, **attrs)
    end
  end

  def rows(doc = Nokogiri::HTML(response.body))
    doc.css("[data-testid=error-row]")
  end

  describe "index" do
    it "counts quarantined failures in their group" do
      timeout = group("Net::ReadTimeout")
      fail_in(timeout)
      run = create(:run, project: project, build: create(:build, project: project, branch: "main"), branch: "main",
                         created_at: 1.day.ago)
      create(:test_result, run: run, test_case: create(:test_case, project: project), status: "quarantined",
                           error_group: timeout, created_at: 1.day.ago)

      get project_errors_path(project)

      expect(rows.size).to eq(1)
      expect(rows.first.css("td")[1].text.strip).to eq("2")
    end

    it "orders groups by failures across pages exactly like the in-Ruby sort did" do
      groups = (1..30).map { |i| group("Error#{i}").tap { |g| fail_in(g, count: i) } }

      get project_errors_path(project)
      first_page = rows.map { |row| row.at_css("span.font-semibold").text }
      get project_errors_path(project, page: 2)
      second_page = rows.map { |row| row.at_css("span.font-semibold").text }

      expect(first_page.size).to eq(25)
      expect(first_page + second_page).to eq(groups.reverse.map(&:exception_class))
    end

    it "breaks failure-count ties by group id" do
      first = group("FirstError")
      second = group("SecondError")
      fail_in(second, count: 2)
      fail_in(first, count: 2)

      get project_errors_path(project)

      expect(rows.map { |row| row.at_css("span.font-semibold").text }).to eq(%w[FirstError SecondError])
    end

    it "clamps an out-of-range page to the last page" do
      (1..26).each { |i| fail_in(group("Error#{i}"), count: i) }

      get project_errors_path(project, page: 99)

      expect(response).to have_http_status(:ok)
      expect(rows.map { |row| row.at_css("span.font-semibold").text }).to eq(%w[Error1])
    end

    it "pages within the branch filter" do
      (1..26).each { |i| fail_in(group("Main#{i}"), count: i) }
      fail_in(group("FeatureError"), branch: "feature")

      get project_errors_path(project, branch: "feature")

      expect(rows.map { |row| row.at_css("span.font-semibold").text }).to eq(%w[FeatureError])
    end

    it "defaults to a 14 day window and falls back on an invalid window" do
      recent = group("RecentError")
      old = group("OldError")
      fail_in(recent, at: 2.days.ago)
      fail_in(old, at: 20.days.ago)
      fail_in(group("TenDayError"), at: 10.days.ago)
      get project_errors_path(project)
      expect(response.body).to include("RecentError")
      expect(response.body).not_to include("OldError")
      get project_errors_path(project, window: "5")
      expect(response.body).not_to include("OldError")
      expect(response.body).to include("TenDayError")
      get project_errors_path(project, window: [ "7" ], page: { a: 1 })
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("TenDayError")
      get project_errors_path(project, window: "90")
      expect(response.body).to include("OldError")
    end

    it "filters by branch and lists only branches with failures in the window" do
      a = group("MainError")
      b = group("FeatureError")
      fail_in(a, branch: "main")
      fail_in(b, branch: "feature/x")
      fail_in(group("StaleError"), branch: "ancient", at: 40.days.ago)
      get project_errors_path(project, branch: "feature/x")
      doc = Nokogiri::HTML(response.body)
      expect(rows(doc).map { |r| r.at_css("span.font-semibold").text }).to eq([ "FeatureError" ])
      expect(doc.css("select[name=branch] option").map(&:text)).to eq([ "All branches", "feature/x", "main" ])
    end

    it "shows failures, distinct tests, distinct builds, first and last seen, sorted by failures" do
      big = group("BigError", first_seen_at: Time.zone.local(2026, 1, 2, 10, 0))
      small = group("SmallError")
      shared = create(:test_case, project: project, full_name: "shared")
      build = create(:build, project: project)
      fail_in(big, build: build, at: 3.days.ago, count: 2)
      run = create(:run, project: project, build: build, created_at: 1.day.ago)
      2.times { create(:test_result, run: run, test_case: shared, status: "failed", error_group: big) }
      fail_in(big, at: 2.days.ago)
      fail_in(small, at: 1.day.ago)
      get project_errors_path(project)
      rs = rows
      expect(rs.map { |r| r.at_css("span.font-semibold").text }).to eq(%w[BigError SmallError])
      cells = rs.first.css("td").map { |td| td.text.squish }
      expect(cells[1..3]).to eq(%w[5 4 2])
      expect(cells[4]).to eq(I18n.l(big.first_seen_at, format: :short))
      expect(cells[5]).to eq(I18n.l(run.created_at, format: :short))
    end

    it "ignores passed results and groups of other projects" do
      mine = group("MineError")
      kase = create(:test_case, project: project)
      run = create(:run, project: project, created_at: 1.day.ago)
      create(:test_result, run: run, test_case: kase, status: "passed", error_group: mine)
      other = create(:error_group, exception_class: "ForeignError")
      fail_in(other)
      get project_errors_path(project)
      expect(response.body).not_to include("MineError", "ForeignError")
      expect(response.body).to include("No errors in the last 14 days")
    end

    it "paginates 25 per page" do
      # Equal failure counts tie-break by group id, so creation order is the sort order.
      30.times { |i| fail_in(group("E#{i.to_s.rjust(2, '0')}")) }
      get project_errors_path(project)
      expect(rows.size).to eq(25)
      get project_errors_path(project, page: 2)
      expect(rows.size).to eq(5)
      expect(rows.map { |r| r.at_css("span.font-semibold").text }).to eq(%w[E25 E26 E27 E28 E29])
      get project_errors_path(project, page: 99)
      expect(rows.size).to eq(5)
    end

    it "keeps the query count constant for 5 and for 60 groups" do
      counts = [ 5, 60 ].map do |n|
        n.times { |i| fail_in(group("Q#{n}-#{i}")) }
        count = 0
        counter = ->(*, payload) { count += 1 unless %w[SCHEMA CACHE TRANSACTION].include?(payload[:name]) }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get project_errors_path(project) }
        count
      end
      expect(counts.last).to eq(counts.first)
    end

    it "shows the Errors link on the project page" do
      get project_path(project)
      expect(response.body).to include(%(href="#{project_errors_path(project)}"), "Errors")
    end
  end

  describe "show" do
    let(:grp) { group("TimeoutError", message: "waited <n>s", frame: "pages/p.rb") }

    it "renders the header and the latest result's escaped sample" do
      fail_in(grp, at: 3.days.ago, failure_message: "old message", backtrace: "old.rb:1")
      fail_in(grp, at: 1.day.ago, failure_message: "<b>new</b> message", backtrace: "a.rb:1\nb.rb:2")
      get project_error_path(project, grp)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("h1").text).to eq("TimeoutError")
      expect(response.body).to include("waited &lt;n&gt;s", "pages/p.rb")
      expect(doc.at_css("pre[data-testid=sample-message]").text).to eq("<b>new</b> message")
      expect(doc.at_css("pre[data-testid=sample-backtrace]").text).to eq("a.rb:1\nb.rb:2")
      expect(response.body).to include("&lt;b&gt;new&lt;/b&gt; message")
      expect(response.body).not_to include("old message")
    end

    it "shows last failed from the run's clock, as the index does" do
      kase = create(:test_case, project: project, full_name: "clocked")
      run = create(:run, project: project, created_at: 2.days.ago)
      create(:test_result, run: run, test_case: kase, status: "failed", error_group: grp, created_at: 5.hours.ago)
      get project_error_path(project, grp)
      item = Nokogiri::HTML(response.body).at_css("[data-testid=affected-tests] li")
      expect(item.text).to include(I18n.l(run.created_at, format: :short))
    end

    it "lists affected tests with counts, capped at 50, linking to the test case" do
      busy = create(:test_case, project: project, full_name: "busy test")
      run = create(:run, project: project, created_at: 1.day.ago)
      2.times { create(:test_result, run: run, test_case: busy, status: "failed", error_group: grp) }
      fail_in(grp, count: 55)
      get project_error_path(project, grp)
      items = Nokogiri::HTML(response.body).css("[data-testid=affected-tests] li")
      expect(items.size).to eq(50)
      expect(items.first.text).to include("busy test", "2 failures")
      expect(items.first.at_css("a")["href"]).to eq(project_test_case_path(project, busy))
    end

    it "lists the 20 most recent builds with branch, commit and link" do
      builds = Array.new(22) do |i|
        build = create(:build, project: project, branch: "br#{i}", commit_sha: "abcdef#{i.to_s.rjust(2, '0')}9", commit_message: "msg #{i}")
        fail_in(grp, build: build, branch: "br#{i}", at: (30 - i).hours.ago)
        build
      end
      get project_error_path(project, grp)
      items = Nokogiri::HTML(response.body).css("[data-testid=recent-builds] li")
      expect(items.size).to eq(20)
      expect(items.first.text).to include("msg 21", "br21", "abcdef2")
      expect(items.first.at_css("a")["href"]).to eq(project_build_path(project, builds.last))
    end

    it "handles a group with no failed results" do
      get project_error_path(project, grp)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No failed results")
    end
  end

  describe "PR comment links" do
    it "resolves the Top errors details link for a member" do
      grp = group("LinkError")
      build = create(:build, project: project)
      fail_in(grp, count: 2, build: build)
      md = BuildSummary.new(build, url: project_build_url(project, build)).markdown
      path = md[%r{\(https?://[^/]+(/projects/[^)]+/errors/\d+)\)}, 1]
      expect(path).to eq(project_error_path(project, grp))
      get path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "access" do
    let(:outsider_group) do
      create(:error_group, exception_class: "SecretError").tap do |g|
        other = g.project
        create(:test_result, run: create(:run, project: other), test_case: create(:test_case, project: other),
                             status: "failed", error_group: g, failure_message: "secret detail")
      end
    end

    it "404s for non-members without leaking" do
      other = create(:project)
      g = create(:error_group, project: other, exception_class: "SecretError")
      create(:test_result, run: create(:run, project: other), test_case: create(:test_case, project: other),
                                           status: "failed", error_group: g, failure_message: "secret detail")
      get project_errors_path(other)
      expect(response).to have_http_status(:not_found)
      get project_error_path(other, g)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("SecretError", "secret detail")
    end

    it "404s for a group id from another project on this project's URL" do
      get project_error_path(project, outsider_group)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("SecretError", "secret detail")
    end

    it "lets every role view" do
      grp = group
      fail_in(grp)
      %w[viewer member].each do |role|
        member = create(:user)
        project.organization.memberships.create!(user: member, role: role)
        delete session_path
        sign_in(member)
        get project_errors_path(project)
        expect(response).to have_http_status(:ok)
        get project_error_path(project, grp)
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "windows with a short result retention" do
    let(:short) { Retention::Config.new(attachment_days: 7, result_days: 14) }

    before { allow(Retention).to receive(:config).and_return(short) }

    it "offers only windows within result retention and defaults to the default" do
      get project_errors_path(project)

      values = Nokogiri::HTML(response.body).css("select[name=window] option").map { |o| o["value"] }
      expect(values).to eq(%w[7 14])
      expect(Nokogiri::HTML(response.body).css("select[name=window] option[selected]").map { |o| o["value"] }).to eq(%w[14])
    end

    it "ignores a requested window beyond retention" do
      get project_errors_path(project, window: 90)

      expect(Nokogiri::HTML(response.body).css("select[name=window] option[selected]").map { |o| o["value"] }).to eq(%w[14])
    end

    it "offers only result_days when no standard window fits" do
      allow(Retention).to receive(:config).and_return(Retention::Config.new(attachment_days: 1, result_days: 3))
      get project_errors_path(project)

      expect(Nokogiri::HTML(response.body).css("select[name=window] option").map { |o| o["value"] }).to eq(%w[3])
    end
  end
end
