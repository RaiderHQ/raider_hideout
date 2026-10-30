require "rails_helper"

RSpec.describe BuildSummary do
  let(:project) { create(:project) }
  let(:build) { create(:build, project: project, status: "failed", total_count: 160, passed_count: 148, failed_count: 2, flaky_count: 1, duration_ms: 65_000) }
  let(:run) { create(:run, project: project, build: build) }
  let(:url) { "https://raider.example/projects/p/builds/1" }

  def result(status:, name: "works", file: "spec/a_spec.rb", message: nil, flaky: false)
    tc = create(:test_case, project: project, full_name: name, file_path: file)
    create(:test_case_verdict, test_case: tc, branch: build.branch, flaky: true) if flaky
    create(:test_result, run: run, test_case: tc, status: status, failure_message: message)
  end

  def markdown = described_class.new(build.reload, url: url).markdown

  describe "#state" do
    it "maps build status" do
      %w[passed failed incomplete].each do |status|
        build.update_columns(status: status)
        expect(described_class.new(build, url: url).state).to eq(status)
      end
    end
  end

  it "starts with the marker line" do
    expect(markdown.lines.first.chomp).to eq("<!-- raider-reporter:build-comment -->")
  end

  it "has a headline with counts" do
    expect(markdown).to include("2 failed, 148 passed")
  end

  describe "headline" do
    let(:gem_counts) { /\b\d+ (?:failed|passed|skipped|pending)\b/ }

    def headline = markdown.lines[2].chomp

    it "pins the full line and stays parseable by the reporter gem" do
      expect(headline).to eq("**Raider: failed** - 2 failed, 148 passed (1m 5s)")
      expect(headline.scan(gem_counts).join(", ")).to eq("2 failed, 148 passed")
    end

    it "shows sub-second durations as <1s" do
      build.update_columns(duration_ms: 400)
      expect(headline).to eq("**Raider: failed** - 2 failed, 148 passed (<1s)")
      expect(headline.scan(gem_counts).join(", ")).to eq("2 failed, 148 passed")
    end

    it "shows shard progress without adding count tokens" do
      build.update_columns(expected_shards: 4, skipped_count: 3, status: "failed")
      create_list(:run, 4, project: project, build: build)
      expect(headline).to eq("**Raider: failed** - 2 failed, 148 passed, 3 skipped (4/4 shards) (1m 5s)")
      expect(headline.scan(gem_counts).join(", ")).to eq("2 failed, 148 passed, 3 skipped")
    end

    it "shows quarantined after failed and stays parseable by the reporter gem" do
      build.update_columns(status: "passed", failed_count: 0, quarantined_count: 1)
      expect(headline).to eq("**Raider: passed** - 1 quarantined, 148 passed (1m 5s)")
      expect(headline.scan(/\b\d+ (?:failed|quarantined|passed|skipped|pending)\b/).join(", ")).to eq("1 quarantined, 148 passed")
    end

    it "is the first line containing Raider:" do
      result(status: "failed", name: "Raider: 9 failed")
      expect(markdown.lines.index { |l| l.include?("Raider:") }).to eq(2)
    end
  end

  it "renders a failures table with file, test and first error line" do
    result(status: "failed", name: "adds", file: "spec/calc_spec.rb", message: "boom\nsecond line")
    md = markdown
    expect(md).to include("| File | Test | Error |")
    expect(md).to include("| spec/calc\\_spec.rb | adds | boom |")
    expect(md).not_to include("second line")
  end

  it "truncates errors to 120 characters" do
    result(status: "failed", message: "x" * 300)
    row = markdown.lines.grep(/\| x+/).first
    expect(row).to include("x" * 120)
    expect(row).not_to include("x" * 121)
  end

  it "limits failures to 10 and reports the rest" do
    12.times { |i| result(status: "failed", name: "t#{i}", message: "m") }
    md = markdown
    expect(md.lines.grep(/\A\| spec\/a\\_spec.rb/).size).to eq(10)
    expect(md).to include("…and 2 more")
  end

  it "lists flaky tests, at most 5" do
    7.times { |i| result(status: "passed", name: "f#{i}", flaky: true) }
    md = markdown
    expect(md.lines.grep(/\A- .*f\d/).size).to eq(5)
    expect(md).to include("…and 2 more")
  end

  it "ignores flaky tests from other builds" do
    other = create(:run, project: project)
    tc = create(:test_case, project: project, full_name: "elsewhere")
    create(:test_case_verdict, test_case: tc, branch: "main", flaky: true)
    create(:test_result, run: other, test_case: tc)
    expect(markdown).not_to include("elsewhere")
  end

  it "lists tests flaky on the build's branch, or on the comparison branch while the branch is thin" do
    build.update!(branch: "feature", default_branch: "main")
    own = result(status: "passed", name: "own")
    create(:test_case_verdict, test_case: own.test_case, branch: "feature", flaky: true)
    inherited = result(status: "passed", name: "inherited")
    create(:test_case_verdict, test_case: inherited.test_case, branch: "feature", flaky: false, sample_count: 2)
    create(:test_case_verdict, test_case: inherited.test_case, branch: "main", flaky: true)
    healed = result(status: "passed", name: "healed")
    create(:test_case_verdict, test_case: healed.test_case, branch: "feature", flaky: false)
    create(:test_case_verdict, test_case: healed.test_case, branch: "main", flaky: true)
    md = markdown
    expect(md).to include("- own (", "- inherited (")
    expect(md).not_to include("- healed (")
  end

  it "links to the build" do
    expect(markdown).to include("[View build](#{url})")
  end

  it "says how many shards are awaited for incomplete builds" do
    build.update_columns(status: "incomplete", expected_shards: 3)
    create(:run, project: project, build: build)
    expect(markdown).to include("Waiting for 2 more shards")
  end

  it "uses the singular for one shard" do
    build.update_columns(status: "incomplete", expected_shards: 2)
    create(:run, project: project, build: build)
    expect(markdown).to include("Waiting for 1 more shard")
    expect(markdown).not_to include("1 more shards")
  end

  it "has no waiting line for complete builds" do
    expect(markdown).not_to include("Waiting for")
  end

  describe "with a baseline" do
    let(:baseline) { create(:build, project: project, branch: "main", status: "passed") }
    let(:baseline_run) { create(:run, project: project, build: baseline) }

    before { build.update!(branch: "feature", baseline_build: baseline, baseline_assigned_at: Time.current) }

    def case_for(name, file: "spec/a_spec.rb") = create(:test_case, project: project, full_name: name, file_path: file)
    def before_status(tc, status) = create(:test_result, run: baseline_run, test_case: tc, status: status)
    def now(tc, status, message: "boom") = create(:test_result, run: run, test_case: tc, status: status, failure_message: message)

    def seed
      still = case_for("still"); fresh = case_for("fresh"); healed = case_for("healed"); other = case_for("other")
      before_status(still, "failed"); before_status(fresh, "passed"); before_status(healed, "failed"); before_status(other, "passed")
      now(still, "failed"); now(other, "failed"); now(fresh, "failed"); now(healed, "passed")
      [ still, fresh, healed, other ]
    end

    def headline = markdown.lines[2].chomp

    it "appends the new failure count to the headline" do
      seed
      expect(headline).to eq("**Raider: failed** - 2 failed, 148 passed (1m 5s) · 2 new failures vs main")
    end

    it "uses the singular and the none form" do
      tc = case_for("one"); before_status(tc, "passed"); now(tc, "failed")
      expect(headline).to end_with(" · 1 new failure vs main")
      baseline_run.test_results.destroy_all
      before_status(tc, "failed")
      expect(headline).to end_with(" · no new failures vs main")
    end

    it "adds a Status column and orders new, still failing, then the rest" do
      _still, _fresh, _healed, other = seed
      create(:test_case_verdict, test_case: other, branch: "feature", flaky: true)
      rows = markdown.lines.grep(/\A\| spec/)
      expect(markdown).to include("| File | Test | Error | Status |", "| --- | --- | --- | --- |")
      expect(rows.map { |r| r.split(" | ").last.strip.delete_suffix(" |") }).to eq([ "New", "Flaky", "Still failing" ])
      expect(rows.map { |r| r.split(" | ")[1] }).to eq([ "fresh", "other", "still" ])
    end

    it "shows Flaky on the default branch for an inherited verdict" do
      _still, _fresh, _healed, other = seed
      create(:test_case_verdict, test_case: other, branch: "main", flaky: true)
      expect(markdown.lines.grep(/\| other \|/).sole).to end_with("| Flaky on main |\n")
    end

    it "is unchanged when the baseline was never assigned" do
      seed
      build.update!(baseline_assigned_at: nil)
      expect(markdown).to include("| File | Test | Error |")
      expect(markdown).not_to include("vs main", "Fixed vs", "Status")
    end

    it "orders by file then test name within a group" do
      %w[b_spec a_spec].each_with_index do |f, i|
        tc = case_for("t#{i}", file: "spec/#{f}.rb"); before_status(tc, "passed"); now(tc, "failed")
      end
      files = markdown.lines.grep(/\A\| spec/).map { |r| r.split(" | ").first }
      expect(files).to eq([ "| spec/a\\_spec.rb", "| spec/b\\_spec.rb" ])
    end

    it "adds the Fixed line only when something was fixed" do
      seed
      expect(markdown).to include("Fixed vs main: 1")
      expect(markdown.index("Fixed vs main")).to be > markdown.index("| other ")
      baseline_run.test_results.destroy_all
      expect(markdown).not_to include("Fixed vs")
    end

    it "escapes the branch name" do
      baseline.update!(branch: "fix|*x*")
      tc = case_for("t"); before_status(tc, "failed"); now(case_for("u"), "passed"); now(tc, "failed")
      before_status(case_for("healed"), "failed"); now(TestCase.find_by(full_name: "healed"), "passed")
      expect(markdown).to include("vs fix\\|\\*x\\*", "Fixed vs fix\\|\\*x\\*: 1")
    end

    it "still truncates at 10 failures, new ones first" do
      12.times { |i| tc = case_for("t#{i}"); before_status(tc, i < 11 ? "failed" : "passed"); now(tc, "failed") }
      md = markdown
      expect(md.lines.grep(/\A\| spec/).size).to eq(10)
      expect(md.lines.grep(/\A\| spec/).first).to include("| t11 |", "| New |")
      expect(md).to include("…and 2 more")
    end
  end

  it "is unchanged without a baseline" do
    result(status: "failed", name: "adds", file: "spec/calc_spec.rb", message: "boom")
    expect(markdown).to eq(<<~MD)
      <!-- raider-reporter:build-comment -->

      **Raider: failed** - 2 failed, 148 passed (1m 5s)

      ### Failed tests

      | File | Test | Error |
      | --- | --- | --- |
      | spec/calc\\_spec.rb | adds | boom |

      [View build](#{url})
    MD
  end

  describe "top errors" do
    def grouped(group, count, status: "failed")
      Array.new(count) do |i|
        tc = create(:test_case, project: project, full_name: "#{group.exception_class} #{SecureRandom.hex(2)} #{i}")
        create(:test_result, run: run, test_case: tc, status: status, error_group: group, failure_message: "x")
      end
    end

    def eg(klass, message: "boom", frame: "")
      create(:error_group, project: project, exception_class: klass, normalized_message: message, frame: frame)
    end

    it "lists groups with 2+ failures before the failed table, most failures first, with exact format" do
      big = eg("Selenium::NoSuchElementError", message: "no element \"...\"", frame: "spec/support/helpers.rb")
      small = eg("TimeoutError")
      grouped(big, 3)
      grouped(small, 2)
      md = markdown
      base = "https://raider.example"
      expect(md).to include(<<~MD)
        ### Top errors

        - **3 tests** · `Selenium::NoSuchElementError` in `spec/support/helpers.rb` — no element "..." ([details](#{base}#{Rails.application.routes.url_helpers.project_error_path(project, big)}))
        - **2 tests** · `TimeoutError` — boom ([details](#{base}#{Rails.application.routes.url_helpers.project_error_path(project, small)}))
      MD
      expect(md.index("### Top errors")).to be < md.index("### Failed tests")
    end

    it "counts quarantined results in a group alongside failed ones" do
      group = eg("TimeoutError")
      grouped(group, 1)
      grouped(group, 1, status: "quarantined")
      expect(markdown).to include("- **2 tests** · `TimeoutError`")
    end

    it "limits to 3 groups and skips groups with a single failure or passed results" do
      groups = %w[A B C D].map { |k| eg("#{k}Error") }
      groups.each_with_index { |g, i| grouped(g, 5 - i) }
      grouped(eg("SoloError"), 1)
      grouped(eg("PassedError"), 4, status: "passed")
      md = markdown
      expect(md.scan(/^- \*\*\d+ tests\*\*/).size).to eq(3)
      expect(md).to include("AError", "BError", "CError")
      expect(md).not_to include("DError", "SoloError", "PassedError")
    end

    it "escapes the message and keeps backticks from breaking code spans" do
      g = eg("Bad`Class", message: "<b>@team #12 |x|</b>", frame: "a`b.rb")
      grouped(g, 2)
      line = markdown.lines.find { |l| l.start_with?("- **2 tests**") }
      expect(line).to include("`Bad'Class` in `a'b.rb`")
      expect(line).to include("\\<b\\>@\u200Bteam #\u200B12 \\|x\\|\\</b\\>")
      expect(line.count("`")).to eq(4)
    end

    it "omits the dash when the normalized message is blank" do
      grouped(eg("QuietError", message: ""), 2)
      line = markdown.lines.find { |l| l.include?("QuietError") }
      expect(line).to match(/`QuietError` \(\[details\]/)
      expect(line).not_to include("  ", "—")
    end

    it "builds the details link from the summary url host" do
      g = eg("HostError")
      grouped(g, 2)
      md = described_class.new(build.reload, url: "http://localhost:3001/projects/p/builds/1").markdown
      expect(md).to match(%r{\(http://localhost:3001/projects/#{project.slug}/errors/#{g.id}\)\)})
    end

    it "uses a constant number of queries" do
      count = lambda do
        n = 0
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless p[:name] == "SCHEMA" }
        markdown
        ActiveSupport::Notifications.unsubscribe(sub)
        n
      end
      grouped(eg("Q1"), 2)
      small = count.call
      3.times { |i| grouped(eg("Q#{i + 2}"), 2) }
      expect(count.call).to eq(small)
    end

    it "is omitted when only single failures are grouped (the snapshot specs pin the bytes)" do
      grouped(eg("SoloError"), 1)
      expect(markdown).not_to include("Top errors")
    end
  end

  describe "escaping" do
    it "neutralises markdown and HTML in names, files and messages" do
      result(status: "failed", name: "a | b *c* `d` <script>x</script> [l](u)\nnext",
             file: "spec/<img>_spec.rb", message: "<b>bad</b> | _x_ \\ \u0007\u001Fctl")
      row = markdown.lines.grep(/script/).sole
      expect(row).to eq(
        "| spec/\\<img\\>\\_spec.rb | a \\| b \\*c\\* \\`d\\` \\<script\\>x\\</script\\> \\[l\\](u) next | " \
        "\\<b\\>bad\\</b\\> \\| \\_x\\_ \\\\ ctl |\n"
      )
    end

    it "neutralises mentions and issue references" do
      [ "@octocat ping", "#<Foo:0x1 @name=\"x\">", "fixes #123", "RaiderHQ/demo#7" ].each_with_index do |name, i|
        result(status: "failed", name: name, message: name, file: "spec/f#{i}.rb")
      end
      md = markdown
      expect(md).not_to match(/@\w/)
      expect(md).not_to match(/#\d/)
      expect(md).not_to match(/#\w/)
      expect(md).to include("@\u200Boctocat", "#\u200B123", "demo#\u200B7")
    end

    it "keeps entities and strikethrough literal" do
      result(status: "failed", name: "&#64;octocat ping &#35;12 ~~x~~")
      row = markdown.lines.grep(/octocat/).sole
      expect(row).to include("\\&#\u200B64;", "\\&#\u200B35;", "\\~\\~x\\~\\~")
      expect(row).not_to match(/(?<!\\)&#/)
    end

    it "strips bidi and format characters" do
      result(status: "failed", name: "abc\u202Edcba\u200F")
      expect(markdown).to include("| abcdcba |")
    end

    it "caps file and test cells at 200 characters" do
      result(status: "failed", name: "n" * 300, file: "f" * 300)
      row = markdown.lines.grep(/nnn/).sole
      expect(row).to include("#{'f' * 200}…", "#{'n' * 200}…")
      expect(row).not_to include("f" * 201)
      expect(row).not_to include("n" * 201)
    end

    it "keeps the query count constant" do
      count = lambda do
        n = 0
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless p[:name] == "SCHEMA" }
        markdown
        ActiveSupport::Notifications.unsubscribe(sub)
        n
      end
      3.times { |i| result(status: "failed", name: "a#{i}", flaky: true) }
      small = count.call
      20.times { |i| result(status: "failed", name: "b#{i}", flaky: true) }
      expect(count.call).to eq(small)
    end

    it "keeps the query count constant with no comparison branch" do
      build.update_columns(branch: "feature", default_branch: nil, pr_base_branch: nil)
      count = lambda do
        n = 0
        sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless p[:name] == "SCHEMA" }
        markdown
        ActiveSupport::Notifications.unsubscribe(sub)
        n
      end
      3.times { |i| result(status: "failed", name: "a#{i}") }
      small = count.call
      20.times { |i| result(status: "failed", name: "b#{i}") }
      expect(count.call).to eq(small)
    end

    it "does not let the marker be forged through test names" do
      result(status: "failed", name: "--> <!-- raider-reporter:build-comment -->")
      expect(markdown.scan("<!-- raider-reporter:build-comment -->").size).to eq(1)
    end
  end

  it "drops the comparison suffix when the baseline expired" do
    baseline = create(:build, project: project, branch: "main")
    create(:run, project: project, build: baseline, results_purged_at: 1.day.ago)
    build.update_columns(branch: "feature", default_branch: "main", baseline_build_id: baseline.id, baseline_assigned_at: Time.current)
    result(status: "failed", message: "boom")

    expect(markdown).not_to include("vs main")
  end

  describe "gate line" do
    def gate_line = markdown.lines.find { |line| line.start_with?("**Gate:**") }&.chomp

    def verdict!(status, rules)
      build.update_columns(gate_status: status, gate_result: JSON.generate("rules" => rules), gate_evaluated_at: Time.current)
    end

    it "is absent without an enabled rule or a passed/failed verdict" do
      expect(gate_line).to be_nil
      create(:gate_rule, project: project)
      expect(gate_line).to be_nil
      verdict!("none", {})
      create(:gate_rule, project: create(:project))
      expect(gate_line).to be_nil
    end

    it "stays absent for a none verdict even after a rule is turned on" do
      verdict!("none", {})
      create(:gate_rule, project: project, min_pass_rate: 98)
      expect(gate_line).to be_nil
    end

    it "shows pending right under the headline when the project has an enabled rule" do
      create(:gate_rule, project: project, min_pass_rate: 98)
      expect(markdown.lines[4].chomp).to eq("**Gate:** ⏳ pending")
    end

    it "shows passed" do
      verdict!("passed", "pass_rate" => { "min" => 90, "actual" => 92, "outcome" => "passed" })
      expect(gate_line).to eq("**Gate:** ✅ passed")
    end

    it "lists the failed rules, escaped for Markdown" do
      verdict!("failed", "pass_rate" => { "min" => 98, "actual" => 96, "outcome" => "failed" },
                         "new_failures" => { "count" => 2, "baseline_build_id" => 1, "branch" => "main", "outcome" => "failed" },
                         "new_flaky" => { "count" => 0, "outcome" => "passed" })
      expect(gate_line).to eq("**Gate:** ❌ failed — pass rate 96% \\< 98%; 2 new failures vs main")
    end

    it "escapes a branch name in a rule detail" do
      verdict!("failed", "new_failures" => { "count" => 1, "baseline_build_id" => 1, "branch" => "feat_<x>", "outcome" => "failed" })
      expect(gate_line).to eq("**Gate:** ❌ failed — 1 new failure vs feat\\_\\<x\\>")
    end
  end
end
