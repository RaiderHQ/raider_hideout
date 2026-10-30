require "rails_helper"

RSpec.describe Builds::Gate do
  include ActiveJob::TestHelper
  include LogCapture

  let(:project) { create(:project) }
  let(:build) { create(:build, project: project, branch: "feature", total_count: 100, passed_count: 96, failed_count: 4) }

  def gate_rule(**attrs) = create(:gate_rule, project: project, **attrs)

  def evaluate(target = build) = described_class.evaluate!(target)

  def stored(target = build) = JSON.parse(target.reload.gate_result)

  def verdict_columns = build.reload.attributes.slice("gate_status", "gate_result", "gate_evaluated_at")

  def kase(name) = create(:test_case, project: project, full_name: name)

  def main_build = create(:build, project: project, branch: "main", created_at: 1.day.ago)

  def result(on, test_case, status)
    run = on.runs.first || create(:run, project: project, build: on, branch: on.branch)
    create(:test_result, run: run, test_case: test_case, status: status)
  end

  describe "without enabled rules" do
    it "writes none with empty rules when the project has no gate rule" do
      expect(evaluate).to be(true)
      expect(build.reload).to have_attributes(gate_status: "none", gate_evaluated_at: be_present)
      expect(stored).to eq("rules" => {})
    end

    it "writes none when every rule is off" do
      gate_rule(min_pass_rate: nil, no_new_failures: false, no_new_flaky: false)
      evaluate
      expect(build.reload.gate_status).to eq("none")
      expect(stored).to eq("rules" => {})
    end
  end

  describe "pass_rate" do
    it "fails below the minimum, stores the rule values used and leaves the other rules out" do
      gate_rule(min_pass_rate: 98)
      evaluate
      expect(build.reload.gate_status).to eq("failed")
      expect(stored).to eq("rules" => { "pass_rate" => { "min" => 98, "actual" => 96, "outcome" => "failed" } },
                           "evaluated_rules" => { "min_pass_rate" => 98, "no_new_failures" => false, "no_new_flaky" => false })
    end

    it "passes at exactly the minimum" do
      gate_rule(min_pass_rate: 96)
      evaluate
      expect(build.reload.gate_status).to eq("passed")
      expect(stored.dig("rules", "pass_rate")).to eq("min" => 96, "actual" => 96, "outcome" => "passed")
    end

    it "floors, so 97.9% is 97 and fails a 98% minimum" do
      build.update_columns(passed_count: 979, failed_count: 21)
      gate_rule(min_pass_rate: 98)
      evaluate
      expect(stored.dig("rules", "pass_rate")).to eq("min" => 98, "actual" => 97, "outcome" => "failed")
    end

    it "ignores quarantined results" do
      build.update_columns(passed_count: 98, failed_count: 0, quarantined_count: 50)
      gate_rule(min_pass_rate: 99)
      evaluate
      expect(stored.dig("rules", "pass_rate")).to eq("min" => 99, "actual" => 100, "outcome" => "passed")
      expect(build.reload.pass_rate).to eq(66)
    end

    it "is skipped with a reason, and does not fail, when nothing passed or failed" do
      build.update_columns(passed_count: 0, failed_count: 0, skipped_count: 5, quarantined_count: 2)
      gate_rule(min_pass_rate: 98)
      evaluate
      expect(build.reload.gate_status).to eq("passed")
      expect(stored.dig("rules", "pass_rate")).to eq("min" => 98, "outcome" => "skipped", "reason" => "no passed or failed results")
    end
  end

  describe "new_failures" do
    it "fails when a test failed now and not on the baseline; a quarantined result is not a failure" do
      main = main_build
      broke = kase("broke")
      held = kase("held")
      result(main, broke, "passed")
      result(main, held, "passed")
      result(build, broke, "failed")
      result(build, held, "quarantined")
      gate_rule(no_new_failures: true)
      Builds::Baseline.assign!(build)

      evaluate

      expect(build.reload.gate_status).to eq("failed")
      expect(stored.dig("rules", "new_failures"))
        .to eq("count" => 1, "baseline_build_id" => main.id, "branch" => "main", "outcome" => "failed")
    end

    it "passes when nothing newly failed" do
      main = main_build
      steady = kase("steady")
      result(main, steady, "failed")
      result(build, steady, "failed")
      gate_rule(no_new_failures: true)
      Builds::Baseline.assign!(build)

      evaluate

      expect(build.reload.gate_status).to eq("passed")
      expect(stored.dig("rules", "new_failures"))
        .to eq("count" => 0, "baseline_build_id" => main.id, "branch" => "main", "outcome" => "passed")
    end

    it "is skipped when the comparison branch has no baseline build" do
      build.update_columns(default_branch: "develop")
      gate_rule(no_new_failures: true)
      Builds::Baseline.assign!(build)
      evaluate
      expect(build.reload.gate_status).to eq("passed")
      expect(stored.dig("rules", "new_failures")).to eq("outcome" => "skipped", "reason" => "no baseline build on develop")
    end

    it "is skipped when no baseline was assigned" do
      main_build
      gate_rule(no_new_failures: true)
      evaluate
      expect(stored.dig("rules", "new_failures")).to eq("outcome" => "skipped", "reason" => "no baseline build on main")
    end

    it "names the default branch when the build has no comparison branch" do
      gate_rule(no_new_failures: true)
      Builds::Baseline.assign!(build)
      evaluate
      expect(stored.dig("rules", "new_failures"))
        .to eq("outcome" => "skipped", "reason" => "no baseline build on the default branch")
    end

    it "is skipped when the baseline's results were purged" do
      main = main_build
      create(:run, project: project, build: main, results_purged_at: Time.current)
      build.update_columns(baseline_build_id: main.id, baseline_assigned_at: Time.current)
      gate_rule(no_new_failures: true)
      evaluate
      expect(stored.dig("rules", "new_failures")).to eq("outcome" => "skipped", "reason" => "baseline results purged")
    end
  end

  describe "new_flaky" do
    it "fails when a test turned flaky on the build's branch in this build" do
      create(:test_case_verdict, test_case: kase("flips"), branch: "feature", flaky: true, flaky_since_build_id: build.id)
      create(:test_case_verdict, test_case: kase("old news"), branch: "feature", flaky: true, flaky_since_build_id: main_build.id)
      gate_rule(no_new_flaky: true)
      evaluate
      expect(build.reload.gate_status).to eq("failed")
      expect(stored.dig("rules", "new_flaky")).to eq("count" => 1, "outcome" => "failed")
    end

    it "passes when nothing turned flaky" do
      gate_rule(no_new_flaky: true)
      evaluate
      expect(stored.dig("rules", "new_flaky")).to eq("count" => 0, "outcome" => "passed")
    end

    it "is skipped for a build without a branch" do
      build.update_columns(branch: nil)
      gate_rule(no_new_flaky: true)
      evaluate
      expect(stored.dig("rules", "new_flaky")).to eq("outcome" => "skipped", "reason" => "no branch")
    end
  end

  describe "overall" do
    it "passes when every enabled rule passed or was skipped" do
      build.update_columns(branch: nil)
      gate_rule(min_pass_rate: 90, no_new_failures: true, no_new_flaky: true)
      evaluate
      expect(build.reload.gate_status).to eq("passed")
      expect(stored["rules"].keys).to eq(%w[pass_rate new_failures new_flaky])
      expect(stored["rules"].values.map { |rule| rule["outcome"] }).to eq(%w[passed skipped skipped])
      expect(stored["evaluated_rules"]).to eq("min_pass_rate" => 90, "no_new_failures" => true, "no_new_flaky" => true)
    end

    it "fails when any one rule failed" do
      build.update_columns(branch: nil)
      gate_rule(min_pass_rate: 98, no_new_failures: true, no_new_flaky: true)
      evaluate
      expect(build.reload.gate_status).to eq("failed")
    end
  end

  describe "write once" do
    before { gate_rule(min_pass_rate: 90) }

    it "writes nothing on a second evaluation, even after the rules and counts changed" do
      expect(evaluate).to be(true)
      first = verdict_columns
      GateRule.find_by(project: project).update!(min_pass_rate: 100)
      build.update_columns(passed_count: 1, failed_count: 99)

      expect(evaluate(Build.find(build.id))).to be(false)
      expect(verdict_columns).to eq(first)
    end

    it "lets only one of two concurrent ready hooks write and broadcast (Review Focus 1)" do
      first_hook = Build.find(build.id)
      second_hook = Build.find(build.id) # loaded before the first write: gate_evaluated_at is nil in memory

      expect { expect(evaluate(first_hook)).to be(true) }.to have_enqueued_job(Turbo::Streams::ActionBroadcastJob)
      GateRule.find_by(project: project).update!(min_pass_rate: 100)
      expect { expect(evaluate(second_hook)).to be(false) }.not_to have_enqueued_job(Turbo::Streams::ActionBroadcastJob)

      expect(build.reload.gate_status).to eq("passed")
      expect(stored.dig("rules", "pass_rate", "min")).to eq(90)
    end
  end

  it "logs an evaluation error with the build id, writes nothing and does not raise" do
    gate_rule(no_new_flaky: true)
    allow(Notifications::Rules).to receive(:new_flaky_scope).and_raise(RuntimeError, "boom")

    log = capture_log { expect(evaluate).to be(false) }

    expect(build.reload).to have_attributes(gate_status: nil, gate_result: nil, gate_evaluated_at: nil)
    expect(log).to include("[gate] build #{build.id}: evaluation failed: RuntimeError: boom")
  end

  it "keeps the written verdict and returns true when only the broadcast fails" do
    gate_rule(min_pass_rate: 90)
    allow_any_instance_of(Build).to receive(:broadcast_replace_later_to).and_raise(RuntimeError, "cable down")

    log = capture_log { expect(evaluate).to be(true) }

    expect(build.reload.gate_status).to eq("passed")
    expect(log).to include("[gate] build #{build.id}: gate verdict broadcast failed: RuntimeError: cable down")
    expect(log).not_to include("evaluation failed")
  end
end
