require "rails_helper"

RSpec.describe FlakinessJob do
  include ActiveJob::TestHelper

  let(:project) { create(:project) }
  let(:test_case) { create(:test_case, project: project) }

  def record(status, branch:, sha:, retried: false)
    run = create(:run, project: project, branch: branch, commit_sha: sha)
    create(:test_result, run: run, test_case: test_case, status: status, retried_flaky: retried)
    run
  end

  it "retries on a database error instead of dropping the analysis" do
    run = record("passed", branch: "main", sha: "a")
    allow(Run).to receive(:find_by).and_raise(ActiveRecord::StatementInvalid, "boom")
    expect { described_class.perform_now(run.id) }.to have_enqueued_job(described_class).with(run.id)
  end

  def verdict(branch = "main")
    TestCaseVerdict.find_by(test_case: test_case, branch: branch)
  end

  it "writes the run branch's verdict with its sample count" do
    record("passed", branch: "main", sha: "a")
    run = record("failed", branch: "main", sha: "a")
    described_class.perform_now(run.id)
    expect(verdict).to have_attributes(flaky: true, flaky_reason: "same_commit", flip_rate: 1.0, sample_count: 2)
  end

  it "treats a quarantined result as a failure when sampling" do
    record("passed", branch: "main", sha: "a")
    run = record("quarantined", branch: "main", sha: "a")
    described_class.perform_now(run.id)
    expect(verdict).to have_attributes(flaky: true, flaky_reason: "same_commit", sample_count: 2)
  end

  it "updates the same row on the next run" do
    record("passed", branch: "main", sha: "a")
    described_class.perform_now(record("failed", branch: "main", sha: "a").id)
    described_class.perform_now(record("passed", branch: "main", sha: "b").id)
    expect(TestCaseVerdict.where(test_case: test_case).count).to eq(1)
    expect(verdict.sample_count).to eq(3)
  end

  it "flags same-commit flakiness and counts it on the run" do
    record("passed", branch: "main", sha: "a")
    run = record("failed", branch: "main", sha: "a")
    described_class.perform_now(run.id)
    expect(verdict).to have_attributes(flaky: true, flaky_reason: "same_commit")
    expect(run.reload.flaky_count).to eq(1)
    expect(run.build.reload.flaky_count).to eq(1)
  end

  it "keeps branches isolated" do
    %w[passed failed passed failed passed failed].each_with_index { |s, i| record(s, branch: "feature", sha: "f#{i}") }
    main_run = record("passed", branch: "main", sha: "m1")
    described_class.perform_now(main_run.id)
    expect(verdict("main")).to have_attributes(flaky: false, sample_count: 1)
    expect(verdict("feature")).to be_nil
  end

  it "writes no verdict for a run without a branch, but still finishes the analysis" do
    record("passed", branch: nil, sha: "x")
    run = record("failed", branch: nil, sha: "x")
    described_class.perform_now(run.id)
    expect(TestCaseVerdict.count).to eq(0)
    expect(run.reload).to have_attributes(flaky_count: 0, flakiness_analyzed_at: be_present)
  end

  it "only looks at the last 20 results" do
    record("passed", branch: "main", sha: "same")
    record("failed", branch: "main", sha: "same")
    run = nil
    20.times { |i| run = record("passed", branch: "main", sha: "n#{i}") }
    described_class.perform_now(run.id)
    expect(verdict).to have_attributes(flaky: false, sample_count: 20)
  end

  it "fills the window with the last 20 executed results, skipping skipped ones" do
    record("passed", branch: "main", sha: "same")
    record("failed", branch: "main", sha: "same")
    run = nil
    18.times do |i|
      record("passed", branch: "main", sha: "n#{i}")
      run = record("skipped", branch: "main", sha: "s#{i}")
    end
    described_class.perform_now(run.id)
    expect(verdict).to have_attributes(flaky: true, flaky_reason: "same_commit", sample_count: 20)
  end

  it "ignores a deleted run" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  describe "flaky_since_build_id" do
    it "is set when a test turns flaky, kept while it stays flaky, and cleared once de-flaked" do
      record("passed", branch: "main", sha: "a")
      run = record("failed", branch: "main", sha: "a")
      described_class.perform_now(run.id)
      expect(verdict.flaky_since_build_id).to eq(run.build_id)

      later = record("failed", branch: "main", sha: "a")
      described_class.perform_now(later.id)
      expect(verdict).to have_attributes(flaky: true, flaky_since_build_id: run.build_id)

      stable = nil
      20.times { |i| stable = record("passed", branch: "main", sha: "n#{i}") }
      described_class.perform_now(stable.id)
      expect(verdict).to have_attributes(flaky: false, flaky_since_build_id: nil)
    end

    it "keeps each branch's row apart: thin feature samples do not touch main's since" do
      record("passed", branch: "main", sha: "a")
      b1 = record("failed", branch: "main", sha: "a")
      described_class.perform_now(b1.id)
      expect(verdict("main").flaky_since_build_id).to eq(b1.build_id)

      feature = record("passed", branch: "feature/x", sha: "f1")
      described_class.perform_now(feature.id)
      expect(verdict("feature/x")).to have_attributes(flaky: false, flaky_since_build_id: nil, sample_count: 1)
      expect(verdict("main")).to have_attributes(flaky: true, flaky_since_build_id: b1.build_id)

      b2 = record("failed", branch: "main", sha: "a")
      described_class.perform_now(b2.id)
      expect(verdict("main")).to have_attributes(flaky: true, flaky_since_build_id: b1.build_id)
    end

    it "does not set since when a concurrent run has already flipped the row to not flaky" do
      record("passed", branch: "main", sha: "a")
      run = record("failed", branch: "main", sha: "a")
      real_upsert = TestCaseVerdict.method(:upsert)
      allow(TestCaseVerdict).to receive(:upsert) do |*args, **kwargs|
        real_upsert.call(*args, **kwargs)
        TestCaseVerdict.where(test_case_id: test_case.id, branch: "main").update_all(flaky: false)
      end
      described_class.perform_now(run.id)
      expect(verdict).to have_attributes(flaky: false, flaky_since_build_id: nil)
    end

    it "does not clear a branch's since on a thinly-sampled not-flaky verdict" do
      row = create(:test_case_verdict, test_case: test_case, branch: "feature", flaky: true,
                                       flaky_since_build: create(:build, project: project))
      run = record("passed", branch: "feature", sha: "f1")
      described_class.perform_now(run.id)
      expect(row.reload).to have_attributes(flaky: false, sample_count: 1, flaky_since_build_id: row.flaky_since_build_id)
    end
  end

  describe "notification trigger" do
    around do |example|
      original = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      example.run
      ActiveJob::Base.queue_adapter = original
    end

    it "evaluates the gate after the baseline and before the notification" do
      run = record("passed", branch: "main", sha: "a")
      calls = []
      allow(Builds::Baseline).to receive(:assign!).and_wrap_original { |m, *a| calls << :assign; m.call(*a) }
      allow(Builds::Gate).to receive(:evaluate!).and_wrap_original { |m, *a| calls << :gate; m.call(*a) }
      allow(NotifyBuildJob).to receive(:perform_later) { calls << :notify }

      described_class.perform_now(run.id)

      expect(calls).to eq(%i[assign gate notify])
      expect(run.build.reload.gate_status).to eq("none")
    end

    it "evaluates the gate only once every run is in and analysed" do
      create(:gate_rule, project: project, min_pass_rate: 50)
      build = create(:build, project: project, expected_shards: 2)
      first = create(:run, project: project, build: build)
      described_class.perform_now(first.id)
      expect(build.reload.gate_evaluated_at).to be_nil

      second = create(:run, project: project, build: build)
      described_class.perform_now(second.id)
      expect(build.reload.gate_status).to eq("passed")
    end

    it "freezes the verdict at the first ready hook when the shard total is unknown (Review Focus 2)" do
      create(:gate_rule, project: project, min_pass_rate: 98)
      build = create(:build, project: project, expected_shards: nil)
      early = create(:run, project: project, build: build, total_count: 4, passed_count: 3, failed_count: 1)
      described_class.perform_now(early.id)
      frozen = build.reload.attributes.slice("gate_status", "gate_result", "gate_evaluated_at")
      expect(frozen["gate_status"]).to eq("failed")

      late = create(:run, project: project, build: build, total_count: 96, passed_count: 96)
      described_class.perform_now(late.id)

      expect(build.reload.passed_count).to eq(99)
      expect(build.attributes.slice("gate_status", "gate_result", "gate_evaluated_at")).to eq(frozen)
    end

    it "still notifies, and leaves the verdict null, when the gate evaluation fails" do
      create(:gate_rule, project: project, no_new_flaky: true)
      run = record("passed", branch: "main", sha: "a")
      allow(Notifications::Rules).to receive(:new_flaky_scope).and_raise(RuntimeError, "boom")

      expect { described_class.perform_now(run.id) }.to have_enqueued_job(NotifyBuildJob).with(run.build_id)
      expect(run.build.reload.gate_evaluated_at).to be_nil
    end

    it "enqueues NotifyBuildJob when the build is complete" do
      run = record("passed", branch: "main", sha: "a")
      expect { described_class.perform_now(run.id) }.to have_enqueued_job(NotifyBuildJob).with(run.build_id)
    end

    it "waits until every run of the build is analysed" do
      build = create(:build, project: project, expected_shards: 2)
      first = create(:run, project: project, build: build)
      second = create(:run, project: project, build: build)
      create(:test_result, run: first, test_case: test_case, status: "passed")
      expect { described_class.perform_now(first.id) }.not_to have_enqueued_job(NotifyBuildJob)
      expect { described_class.perform_now(second.id) }.to have_enqueued_job(NotifyBuildJob).with(build.id)
    end

    it "assigns the baseline before the notification is enqueued" do
      older = create(:build, project: project, branch: "main", created_at: 1.day.ago)
      create(:run, project: project, build: older)
      run = record("passed", branch: "feature", sha: "a")
      calls = []
      allow(Builds::Baseline).to receive(:assign!).and_wrap_original { |m, *a| calls << :assign; m.call(*a) }
      allow(NotifyBuildJob).to receive(:perform_later) { calls << :notify }
      described_class.perform_now(run.id)
      expect(calls).to eq(%i[assign notify])
      expect(run.build.reload).to have_attributes(baseline_build_id: older.id, baseline_assigned_at: be_present)
    end

    it "assigns no baseline to an incomplete build" do
      build = create(:build, project: project, expected_shards: 2)
      run = create(:run, project: project, build: build)
      create(:test_result, run: run, test_case: test_case, status: "passed")
      described_class.perform_now(run.id)
      expect(build.reload.baseline_assigned_at).to be_nil
    end

    it "does not enqueue while shards are missing" do
      build = create(:build, project: project, expected_shards: 2)
      run = create(:run, project: project, build: build)
      create(:test_result, run: run, test_case: test_case, status: "passed")
      expect { described_class.perform_now(run.id) }.not_to have_enqueued_job(NotifyBuildJob)
    end
  end
end
