require "rails_helper"

RSpec.describe Builds::Comparison do
  let(:project) { create(:project) }
  let(:baseline) { create(:build, project: project, branch: "main") }
  let(:build) { create(:build, project: project, branch: "feature", baseline_build: baseline) }
  let(:comparison) { described_class.new(build) }

  def kase(name, file: "spec/a_spec.rb")
    create(:test_case, project: project, full_name: name, file_path: file)
  end

  def result(on, test_case, status, shard: nil)
    run = on.runs.first || create(:run, project: project, build: on)
    run = create(:run, project: project, build: on) if shard == :other
    create(:test_result, run: run, test_case: test_case, status: status)
  end

  it "sorts each bucket into new failures, still failing, fixed and new tests" do
    broke = kase("broke"); skipped_before = kase("was skipped"); bad = kase("bad"); healed = kase("healed")
    fresh = kase("fresh"); fresh_bad = kase("fresh bad", file: "spec/0_spec.rb"); steady = kase("steady")
    { broke => "passed", skipped_before => "skipped", bad => "failed", healed => "failed", steady => "passed" }
      .each { |tc, st| result(baseline, tc, st) }
    { broke => "failed", skipped_before => "failed", bad => "failed", healed => "passed",
      fresh => "passed", fresh_bad => "failed", steady => "passed" }.each { |tc, st| result(build, tc, st) }

    expect(comparison).to be_available
    expect(comparison.baseline).to eq(baseline)
    expect(comparison.branch).to eq("main")
    expect(comparison.new_failures).to eq([ fresh_bad, broke, skipped_before ].sort_by { |t| [ t.file_path, t.full_name ] })
    expect(comparison.still_failing).to eq([ bad ])
    expect(comparison.fixed).to eq([ healed ])
    expect(comparison.new_tests).to eq([ fresh_bad, fresh ])
    expect(comparison.counts).to eq(new_failures: 3, still_failing: 1, fixed: 1, new_tests: 2)
    expect(comparison.status_for(broke.id)).to eq(:new_failure)
    expect(comparison.status_for(bad.id)).to eq(:still_failing)
    expect(comparison.status_for(healed.id)).to be_nil
    expect(comparison.new_test?(fresh.id)).to be(true)
    expect(comparison.new_test?(steady.id)).to be(false)
  end

  it "counts a test failed on one shard and passed on another as failed" do
    t = kase("sharded")
    result(baseline, t, "passed")
    result(build, t, "failed")
    result(build, t, "passed", shard: :other)
    expect(comparison.new_failures).to eq([ t ])
  end

  it "puts a test that is only skipped now in no bucket, even if it failed in the baseline" do
    t = kase("gone quiet")
    result(baseline, t, "failed")
    result(build, t, "skipped")
    expect(comparison.counts).to eq(new_failures: 0, still_failing: 0, fixed: 0, new_tests: 0)
    expect(comparison.status_for(t.id)).to be_nil
  end

  it "puts a test failed on the baseline and quarantined now in neither fixed nor still failing" do
    t = kase("held now")
    result(baseline, t, "failed")
    result(build, t, "quarantined")
    expect(comparison.counts).to eq(new_failures: 0, still_failing: 0, fixed: 0, new_tests: 0)
    expect(comparison.status_for(t.id)).to be_nil
  end

  it "treats a failing test whose baseline was skipped-only as a new failure" do
    t = kase("woke up")
    result(baseline, t, "skipped")
    result(build, t, "failed")
    expect(comparison.new_failures).to eq([ t ])
    expect(comparison.new_tests).to eq([])
  end

  it "shows a renamed test under new tests and new failures, with the old key gone" do
    old = kase("old name"); renamed = kase("new name")
    result(baseline, old, "passed")
    result(build, renamed, "failed")
    expect(comparison.new_tests).to eq([ renamed ])
    expect(comparison.new_failures).to eq([ renamed ])
    expect(comparison.fixed).to eq([])
  end

  it "is unavailable without a baseline and returns empty buckets" do
    solo = described_class.new(create(:build, project: project))
    expect(solo).not_to be_available
    expect(solo.branch).to be_nil
    expect([ solo.new_failures, solo.still_failing, solo.fixed, solo.new_tests ]).to all(eq([]))
    expect(solo.counts).to eq(new_failures: 0, still_failing: 0, fixed: 0, new_tests: 0)
    expect(solo.status_for(1)).to be_nil
    expect(solo.new_test?(1)).to be(false)
  end

  it "runs a constant number of queries" do
    cases = Array.new(30) { |i| kase("t#{i}") }
    cases.each { |t| result(baseline, t, "passed") }
    cases.each { |t| result(build, t, "failed") }
    fresh = described_class.new(Build.find(build.id))
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" || payload[:cached] }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      fresh.counts
      fresh.new_failures
      fresh.fixed
    end
    expect(count).to be <= 6
  end

  describe "with an expired baseline" do
    let(:build) { create(:build, project: project, branch: "feature", baseline_build: baseline, baseline_assigned_at: Time.current) }

    before do
      create(:run, project: project, build: baseline, results_purged_at: 1.day.ago)
      run = create(:run, project: project, build: build)
      create(:test_result, run: run, status: "failed")
    end

    it "is expired, with empty buckets and no per-test status" do
      test_case_id = build.runs.first.test_results.first.test_case_id
      expect(comparison).to be_available
      expect(comparison).to be_expired
      expect(comparison.counts.values).to all(eq(0))
      expect(comparison.status_for(test_case_id)).to be_nil
      expect(comparison.new_test?(test_case_id)).to be(false)
    end
  end
end
