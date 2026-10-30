require "rails_helper"

RSpec.describe "Build detail", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }

  before { sign_in(user) }

  def add_result(run, file:, name:, status: "passed")
    kase = create(:test_case, project: project, file_path: file, full_name: name)
    create(:test_result, run: run, test_case: kase, status: status)
  end

  it "shows summary tiles for the build" do
    build = create(:build, project: project, passed_count: 7, failed_count: 2, total_count: 9, commit_message: "Ship it")
    get project_build_path(project, build)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ship it", "Total", "Passed", "Failed", "Duration")
  end

  it "shows a Quarantined tile so the tiles sum to Total" do
    build = create(:build, project: project, total_count: 10, passed_count: 5, failed_count: 1, skipped_count: 1,
                           pending_count: 1, quarantined_count: 2)
    get project_build_path(project, build)
    tiles = Nokogiri::HTML(response.body).css("[data-testid=build-tile]").to_h { |tile| [ tile.css("p").last.text, tile.css("p").first.text ] }
    expect(tiles).to include("Total" => "10", "Passed" => "5", "Failed" => "1", "Skipped" => "2", "Quarantined" => "2")
    expect(tiles.values_at("Passed", "Failed", "Skipped", "Quarantined").sum(&:to_i)).to eq(10)
  end

  it "pills tests flaky by the build branch's verdict on the build and run pages" do
    build = create(:build, project: project, branch: "feature", default_branch: "main")
    run = create(:run, project: project, build: build, branch: "feature")
    inherited = add_result(run, file: "spec/a_spec.rb", name: "Inherited")
    create(:test_case_verdict, test_case: inherited.test_case, branch: "main", flaky: true)
    healed = add_result(run, file: "spec/a_spec.rb", name: "Healed")
    create(:test_case_verdict, test_case: healed.test_case, branch: "feature", flaky: false)
    create(:test_case_verdict, test_case: healed.test_case, branch: "main", flaky: true)

    [ project_build_path(project, build), project_run_path(project, run) ].each do |path|
      get path
      cards = Nokogiri::HTML(response.body).css("details > summary").to_h { |summary| [ summary.css("span.flex-1").text, summary.text ] }
      expect(cards["Inherited"]).to include("flaky")
      expect(cards["Healed"]).not_to include("flaky")
    end
  end

  it "renders one chip per run, ordered by label then index, each linking to its run" do
    build = create(:build, project: project)
    b2 = create(:run, project: project, build: build, shard_label: "b", shard_index: 2)
    b1 = create(:run, project: project, build: build, shard_label: "b", shard_index: 1)
    a1 = create(:run, project: project, build: build, shard_label: "a", shard_index: 1)
    bare = create(:run, project: project, build: build)
    get project_build_path(project, build)
    body = response.body
    [ a1, b1, b2, bare ].each { |r| expect(body).to include(%(href="#{project_run_path(project, r)}")) }
    expect(body).to include("Run ##{bare.id}")
    positions = [ a1, b1, b2 ].map { |r| body.index(%(href="#{project_run_path(project, r)}")) }
    expect(positions).to eq(positions.sort)
  end

  it "merges results across shards grouped by file with failures first" do
    build = create(:build, project: project)
    r1 = create(:run, project: project, build: build)
    r2 = create(:run, project: project, build: build)
    add_result(r1, file: "spec/cart_spec.rb", name: "Cart adds")
    add_result(r2, file: "spec/login_spec.rb", name: "Login fails", status: "failed")
    get project_build_path(project, build)
    body = response.body
    expect(body).to include("Cart adds", "Login fails")
    expect(body.index("spec/login_spec.rb")).to be < body.index("spec/cart_spec.rb")
  end

  it "orders chips by job prefix then numeric shard index" do
    build = create(:build, project: project)
    labels = [ "rspec#10", "rspec#2", "rspec#1.2", "rspec#1.1", "lint#3" ]
    runs = labels.to_h { |label| [ label, create(:run, project: project, build: build, shard_label: label) ] }
    get project_build_path(project, build)
    order = [ "lint#3", "rspec#1.1", "rspec#1.2", "rspec#2", "rspec#10" ]
    positions = order.map { |label| response.body.index(%(href="#{project_run_path(project, runs[label])}")) }
    expect(positions).to eq(positions.sort)
  end

  it "orders cards deterministically: failed first, then name, then run" do
    build = create(:build, project: project)
    r1 = create(:run, project: project, build: build)
    r2 = create(:run, project: project, build: build)
    add_result(r1, file: "spec/a_spec.rb", name: "Zeta passes")
    add_result(r2, file: "spec/a_spec.rb", name: "Alpha passes")
    add_result(r2, file: "spec/a_spec.rb", name: "Omega fails", status: "failed")
    get project_build_path(project, build)
    positions = [ "Omega fails", "Alpha passes", "Zeta passes" ].map { |name| response.body.index(name) }
    expect(positions).to eq(positions.sort)
  end

  it "tags each card with its shard when the same test ran in several shards" do
    build = create(:build, project: project)
    kase = create(:test_case, project: project, file_path: "spec/dup_spec.rb", full_name: "Dup test")
    [ 2, 1 ].each do |i|
      run = create(:run, project: project, build: build, shard_label: "job##{i}", shard_index: i)
      create(:test_result, run: run, test_case: kase)
    end
    get project_build_path(project, build)
    cards = response.body[/<main.*<\/main>/m].scan(/<details.*?<\/summary>/m)
    expect(cards.size).to eq(2)
    expect(cards.map { |c| c[/data-shard-tag[^>]*>([^<]*)</, 1] }).to contain_exactly("job#1", "job#2")
  end

  it "does not tag cards for a single-run build" do
    build = create(:build, project: project)
    run = create(:run, project: project, build: build, shard_label: "job#1")
    add_result(run, file: "spec/one_spec.rb", name: "Solo")
    get project_build_path(project, build)
    expect(response.body).not_to include("data-shard-tag")
  end

  it "links CI only for http(s) ci_url" do
    ok = create(:build, project: project, ci_url: "https://ci.example.com/1")
    get project_build_path(project, ok)
    expect(response.body).to include('href="https://ci.example.com/1"', "noopener noreferrer")
    bad = create(:build, project: project, ci_url: "javascript:alert(1)")
    get project_build_path(project, bad)
    expect(response.body).not_to include("javascript:")
  end

  it "labels the CI link by provider and links the PR chip to pr_url" do
    azure = create(:build, project: project, provider: "azure_pipelines", ci_url: "https://dev.azure.com/o/P/_build/results?buildId=1",
                           pr_number: 7, pr_url: "https://dev.azure.com/o/P/_git/r/pullrequest/7")
    get project_build_path(project, azure)
    expect(response.body).to include("Azure Pipelines build", 'href="https://dev.azure.com/o/P/_git/r/pullrequest/7"')
    plain = create(:build, project: project, provider: nil, ci_url: "https://ci.example.com/2")
    get project_build_path(project, plain)
    expect(response.body).to include("CI build")
  end

  it "404s for another user's build" do
    get project_build_path(project, create(:build))
    expect(response).to have_http_status(:not_found)
  end

  it "does not grow queries with shard count (4 shards x 10 results)" do
    build = create(:build, project: project, expected_shards: 4)
    4.times do |i|
      run = create(:run, project: project, build: build, shard_label: "job##{i + 1}", shard_index: i + 1, shard_total: 4)
      10.times { |j| add_result(run, file: "spec/f#{i}_spec.rb", name: "T #{i}-#{j}") }
    end
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA CACHE TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get project_build_path(project, build) }
    expect(response).to have_http_status(:ok)
    # 14: the per-branch verdict lookup, the comparison-branch query and the gate-rule lookup add one each, per request.
    expect(count).to be <= 14
  end

  it "keeps the query count flat when the build has no comparison branch" do
    build = create(:build, project: project, branch: "feature", default_branch: nil, pr_base_branch: nil, expected_shards: 1)
    run = create(:run, project: project, build: build, flakiness_analyzed_at: Time.current)
    5.times { |j| add_result(run, file: "spec/n_spec.rb", name: "N #{j}") }
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA CACHE TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get project_build_path(project, build) }
    expect(response).to have_http_status(:ok)
    expect(count).to be <= 14
  end

  describe "branch comparison" do
    let(:baseline) { create(:build, project: project, branch: "main", status: "passed") }
    let(:build) { create(:build, project: project, branch: "feature", default_branch: "main", status: "failed", baseline_build: baseline, baseline_assigned_at: Time.current) }
    let(:run) { create(:run, project: project, build: build, branch: "feature", flakiness_analyzed_at: Time.current) }
    let(:base_run) { create(:run, project: project, build: baseline, branch: "main", flakiness_analyzed_at: Time.current) }

    def page
      get project_build_path(project, build)
      Nokogiri::HTML(response.body)
    end

    def kase(name, current:, before: nil)
      test_case = create(:test_case, project: project, file_path: "spec/#{name}_spec.rb", full_name: name)
      create(:test_result, run: run, test_case: test_case, status: current)
      create(:test_result, run: base_run, test_case: test_case, status: before) if before
      test_case
    end

    it "shows heading, counts and lists with links when a baseline exists" do
      kase("Brand new fail", current: "failed", before: "passed")
      kase("Old fail", current: "failed", before: "failed")
      kase("Healed", current: "passed", before: "failed")
      fresh = kase("Fresh", current: "passed")
      doc = page
      comparison = doc.at_css("[data-testid=comparison]")
      expect(comparison.at_css("h2").text).to include("Compared with main", "build ##{baseline.id}")
      expect(comparison.at_css("h2 a")["href"]).to eq(project_build_path(project, baseline))
      counts = comparison.css("details[data-bucket]").to_h { |d| [ d["data-bucket"], d.at_css("summary span:last-child").text ] }
      expect(counts).to eq("new_failures" => "1", "still_failing" => "1", "fixed" => "1", "new_tests" => "1")
      fresh_list = comparison.at_css("details[data-bucket=new_tests]")
      expect(fresh_list.text).to include("Fresh", "spec/Fresh_spec.rb")
      expect(fresh_list.at_css("a")["href"]).to eq(project_test_case_path(project, fresh))
    end

    it "caps each list at 50 with an 'and N more' line" do
      52.times { |i| kase("T#{i}", current: "passed") }
      list = page.at_css("details[data-bucket=new_tests]")
      expect(list.css("li").size).to eq(51)
      expect(list.text).to include("and 2 more")
    end

    it "shows the no-baseline copy with the comparison branch" do
      build.update!(baseline_build: nil)
      expect(page.at_css("[data-testid=comparison]").text.squish).to include(
        "No baseline yet — once a build on main completes, builds will be compared with it.")
    end

    it "says 'the default branch' when the build has no comparison branch, and survives a deleted baseline" do
      build.update!(baseline_build: nil, default_branch: nil, pr_base_branch: nil)
      baseline.destroy
      run
      expect(page.at_css("[data-testid=comparison]").text.squish).to include("once a build on the default branch completes")
    end

    it "shows no panel for a build whose baseline was never assigned (pre-existing builds)" do
      build.update!(baseline_build: nil, baseline_assigned_at: nil)
      run
      expect(page.at_css("[data-testid=comparison]")).to be_nil
    end

    it "omits the panel while the build is not ready" do
      run.update!(flakiness_analyzed_at: nil)
      expect(page.at_css("[data-testid=comparison]")).to be_nil
    end

    it "tags each failure by priority" do
      own = kase("Own flaky", current: "failed", before: "failed")
      inherited = kase("Inherited flaky", current: "failed", before: "failed")
      kase("Brand new", current: "failed", before: "passed")
      kase("Still", current: "failed", before: "failed")
      kase("Plain passing", current: "passed", before: "passed")
      create(:test_case_verdict, test_case: own, branch: "feature", flaky: true)
      create(:test_case_verdict, test_case: inherited, branch: "main", flaky: true)
      tags = page.css("details > summary").select { |s| s.at_css("span.flex-1") }.to_h { |s| [ s.at_css("span.flex-1").text, s.at_css("[data-testid=failure-tag]")&.text ] }
      expect(tags).to include("Own flaky" => "Flaky", "Inherited flaky" => "Flaky on main", "Brand new" => "New",
                              "Still" => "Still failing", "Plain passing" => nil)
    end

    it "tags a test failing on one shard and passing on another as failed" do
      test_case = kase("Split", current: "failed", before: "passed")
      other = create(:run, project: project, build: build, branch: "feature", flakiness_analyzed_at: Time.current)
      create(:test_result, run: other, test_case: test_case, status: "passed")
      expect(page.css("[data-testid=failure-tag]").map(&:text)).to eq([ "New" ])
    end

    it "does not grow queries with failure count" do
      counts = [ 3, 30 ].map do |n|
        n.times { |i| kase("F#{n}-#{i}", current: "failed", before: %w[passed failed].sample) }
        count = 0
        counter = ->(*, payload) { count += 1 unless %w[SCHEMA CACHE TRANSACTION].include?(payload[:name]) }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get project_build_path(project, build) }
        count
      end
      expect(counts.last).to eq(counts.first)
    end
  end

  describe "error groups" do
    let(:build) { create(:build, project: project, status: "failed") }
    let(:run) { create(:run, project: project, build: build) }

    def fail_in(group, name, message: "boom", status: "failed")
      kase = create(:test_case, project: project, file_path: "spec/#{name}_spec.rb", full_name: name)
      create(:test_result, run: run, test_case: kase, status: status, error_group: group, exception_class: group&.exception_class, failure_message: message)
    end

    def group(klass, message: "boom", frame: "spec/x.rb")
      create(:error_group, project: project, exception_class: klass, normalized_message: message, frame: frame)
    end

    def page
      get project_build_path(project, build)
      Nokogiri::HTML(response.body)
    end

    it "shows the panel with sorted rows, details, links and Other failures" do
      small = group("AError", message: "small")
      big = group("ZError", message: "big", frame: "pages/p.rb")
      lone = group("LoneError")
      2.times { |i| fail_in(small, "s#{i}") }
      3.times { |i| fail_in(big, "b#{i}") }
      fail_in(lone, "solo")
      doc = page
      expect(doc.at_css("[data-testid=error-groups] h2").text).to eq("Error groups")
      rows = doc.css("[data-testid=error-group-row]")
      expect(rows.map { |r| r.at_css("span.font-semibold").text }).to eq(%w[ZError AError])
      expect(rows.first.text).to include("big", "pages/p.rb", "3 tests")
      expect(rows.first.at_css("a")["href"]).to eq(project_error_path(project, big))
      expect(rows.first.css("details li").size).to eq(3)
      expect(doc.at_css("[data-testid=other-failures] summary").text).to eq("Other failures (1)")
    end

    it "pills only failures whose group has two or more" do
      many = group("ManyError")
      lone = group("LoneError")
      2.times { |i| fail_in(many, "m#{i}") }
      fail_in(lone, "solo")
      pills = page.css("[data-testid=group-pill]")
      expect(pills.map(&:text)).to eq([ "Group · 2 tests" ] * 2)
      expect(pills.first["href"]).to eq(project_error_path(project, many))
    end

    it "counts a quarantined result in its error group" do
      many = group("ManyError")
      fail_in(many, "f0")
      fail_in(many, "q0", status: "quarantined")
      expect(page.css("[data-testid=group-pill]").map(&:text)).to eq([ "Group · 2 tests" ] * 2)
    end

    it "hides the panel and pills when every group has one failure" do
      fail_in(group("AError"), "a")
      fail_in(group("BError"), "b")
      doc = page
      expect(doc.at_css("[data-testid=error-groups]")).to be_nil
      expect(doc.at_css("[data-testid=group-pill]")).to be_nil
    end

    it "hides the panel for a passing build" do
      add_result(run, file: "spec/a_spec.rb", name: "ok")
      expect(page.at_css("[data-testid=error-groups]")).to be_nil
    end

    it "places the panel after the comparison and before file results" do
      baseline = create(:build, project: project, branch: "main", status: "passed")
      build.update!(baseline_build: baseline, baseline_assigned_at: Time.current, branch: "feature", default_branch: "main")
      run.update!(flakiness_analyzed_at: Time.current)
      shared = group("ManyError")
      2.times { |i| fail_in(shared, "m#{i}") }
      body = page.to_html
      expect(body.index("data-testid=\"comparison\"")).to be < body.index("data-testid=\"error-groups\"")
      expect(body.index("data-testid=\"error-groups\"")).to be < body.index("<h2 class=\"font-mono")
    end

    it "escapes HTML in exception messages" do
      evil = group("EvilError", message: "<script>alert(1)</script>")
      2.times { |i| fail_in(evil, "e#{i}") }
      get project_build_path(project, build)
      expect(response.body).not_to include("<script>alert(1)</script>")
      expect(response.body).to include("&lt;script&gt;alert(1)&lt;/script&gt;")
    end

    it "counts a group's failures across runs of the build" do
      other_run = create(:run, project: project, build: build)
      shared = group("SpreadError")
      fail_in(shared, "one")
      kase = create(:test_case, project: project, file_path: "spec/two_spec.rb", full_name: "two")
      create(:test_result, run: other_run, test_case: kase, status: "failed", error_group: shared)
      doc = page
      rows = doc.css("[data-testid=error-group-row]")
      expect(rows.size).to eq(1)
      expect(rows.first.text).to include("2 tests")
      expect(rows.first.css("details li").size).to eq(2)
      expect(doc.css("[data-testid=group-pill]").map(&:text)).to eq([ "Group · 2 tests" ] * 2)
    end

    it "breaks count ties by exception class" do
      zed = group("ZedError")
      alpha = group("AlphaError")
      2.times { |i| fail_in(zed, "z#{i}") }
      2.times { |i| fail_in(alpha, "a#{i}") }
      rows = page.css("[data-testid=error-group-row]")
      expect(rows.map { |r| r.at_css("span.font-semibold").text }).to eq(%w[AlphaError ZedError])
    end

    it "ignores a group from another project" do
      foreign = create(:error_group, exception_class: "ForeignError")
      2.times { |i| fail_in(foreign, "f#{i}") }
      doc = page
      expect(response).to have_http_status(:ok)
      expect(doc.at_css("[data-testid=error-groups]")).to be_nil
      expect(doc.at_css("[data-testid=group-pill]")).to be_nil
    end

    it "does not grow queries with failure count" do
      counts = [ 3, 60 ].map do |n|
        groups = Array.new(10) { |i| group("E#{n}#{i}") }
        n.times { |i| fail_in(groups[i % 10], "q#{n}-#{i}") }
        count = 0
        counter = ->(*, payload) { count += 1 unless %w[SCHEMA CACHE TRANSACTION].include?(payload[:name]) }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get project_build_path(project, build) }
        count
      end
      expect(counts.last).to eq(counts.first)
    end
  end

  it "shows N quarantined on the build and run pages and keeps the quarantined failure" do
    build = create(:build, project: project, status: "passed", passed_count: 1, quarantined_count: 1, total_count: 2)
    run = create(:run, project: project, build: build, quarantined_count: 1, passed_count: 1, total_count: 2)
    flaky = add_result(run, file: "spec/a_spec.rb", name: "Flaky one", status: "quarantined")
    flaky.update!(failure_message: "Net::ReadTimeout", exception_class: "Net::ReadTimeout")

    get project_build_path(project, build)
    expect(Nokogiri::HTML(response.body).at_css("[data-testid=quarantined-count]").text.squish).to eq("1 quarantined")
    expect(response.body).to include("Net::ReadTimeout", "text-status-quarantine bg-status-quarantine-bg")

    get project_run_path(project, run)
    expect(Nokogiri::HTML(response.body).at_css("[data-testid=quarantined-count]").text.squish).to eq("1 quarantined")

    get project_builds_path(project)
    expect(response.body).to include("1 quarantined")
  end

  it "does not mention quarantine when there are none" do
    build = create(:build, project: project)
    get project_build_path(project, build)
    expect(response.body).not_to include("quarantined-count")
  end
end
