require "rails_helper"

RSpec.describe Build do
  let(:project) { create(:project) }
  let(:build_record) { create(:build, project: project) }

  def add_run(attrs = {})
    create(:run, { project: project, build: build_record }.merge(attrs))
  end

  describe "#recompute!" do
    it "sums quarantined counts without failing the build" do
      add_run(status: "passed", total_count: 3, passed_count: 2, quarantined_count: 1)
      add_run(status: "passed", total_count: 2, passed_count: 1, quarantined_count: 1)
      build_record.recompute!
      expect(build_record).to have_attributes(status: "passed", quarantined_count: 2, failed_count: 0, total_count: 5)
    end

    it "marks the build passed and sums counts across runs" do
      add_run(total_count: 5, passed_count: 4, skipped_count: 1)
      add_run(total_count: 3, passed_count: 2, pending_count: 1)
      build_record.recompute!
      expect(build_record).to have_attributes(status: "passed", total_count: 8, passed_count: 6, failed_count: 0,
                                              skipped_count: 1, pending_count: 1)
    end

    it "marks the build failed when any run failed" do
      add_run(status: "passed", total_count: 2, passed_count: 2)
      add_run(status: "failed", total_count: 2, passed_count: 1, failed_count: 1)
      build_record.update!(expected_shards: 4)
      build_record.recompute!
      expect(build_record.status).to eq("failed")
      expect(build_record.failed_count).to eq(1)
    end

    it "marks the build incomplete when fewer runs than expected shards arrived" do
      add_run(shard_index: 1, shard_total: 4)
      add_run(shard_index: 2, shard_total: 4)
      build_record.recompute!
      expect(build_record).to have_attributes(status: "incomplete", expected_shards: 4)
      expect(build_record.shard_progress).to eq("2/4")
    end

    it "is passed once all expected shards arrived" do
      2.times { |i| add_run(shard_index: i + 1, shard_total: 2) }
      build_record.recompute!
      expect(build_record.status).to eq("passed")
      expect(build_record.shard_progress).to eq("2/2")
    end

    it "counts distinct flaky test cases across runs" do
      flaky, steady, other_flaky = create_list(:test_case, 3, project: project)
      [ [ flaky, true ], [ steady, false ], [ other_flaky, true ] ].each do |test_case, value|
        create(:test_case_verdict, test_case: test_case, branch: "main", flaky: value)
      end
      run_a = add_run
      run_b = add_run
      [ [ run_a, flaky ], [ run_b, flaky ], [ run_a, steady ], [ run_b, other_flaky ] ].each do |run, test_case|
        create(:test_result, run: run, test_case: test_case)
      end
      build_record.recompute!
      expect(build_record.flaky_count).to eq(2)
    end

    it "counts flaky by the build branch's verdict, falling back to the comparison branch" do
      build_record.update!(branch: "feature", default_branch: "main")
      own, fallback, thin_flaky, healed = create_list(:test_case, 4, project: project)
      create(:test_case_verdict, test_case: own, branch: "feature", flaky: true, sample_count: 5)
      create(:test_case_verdict, test_case: fallback, branch: "feature", flaky: false, sample_count: 2)
      create(:test_case_verdict, test_case: fallback, branch: "main", flaky: true)
      create(:test_case_verdict, test_case: thin_flaky, branch: "feature", flaky: true, sample_count: 2)
      create(:test_case_verdict, test_case: healed, branch: "feature", flaky: false, sample_count: 5)
      create(:test_case_verdict, test_case: healed, branch: "main", flaky: true)
      run = add_run(branch: "feature")
      [ own, fallback, thin_flaky, healed ].each { |test_case| create(:test_result, run: run, test_case: test_case) }
      build_record.recompute!
      expect(build_record.flaky_count).to eq(3) # own, fallback, and the thin but positive thin_flaky
    end

    it "uses min started_at, max finished_at and derives the duration" do
      add_run(started_at: Time.utc(2026, 1, 1, 10, 0, 5), finished_at: Time.utc(2026, 1, 1, 10, 1, 0))
      add_run(started_at: Time.utc(2026, 1, 1, 10, 0, 0), finished_at: Time.utc(2026, 1, 1, 10, 0, 30))
      build_record.recompute!
      expect(build_record.started_at).to eq(Time.utc(2026, 1, 1, 10, 0, 0))
      expect(build_record.finished_at).to eq(Time.utc(2026, 1, 1, 10, 1, 0))
      expect(build_record.duration_ms).to eq(60_000)
    end
  end

  it "computes pass rate from passed, failed and quarantined only" do
    expect(build(:build, passed_count: 3, failed_count: 1, skipped_count: 9).pass_rate).to eq(75)
    expect(build(:build, passed_count: 1, failed_count: 0, quarantined_count: 3).pass_rate).to eq(25)
    expect(build(:build, quarantined_count: 2).pass_rate).to eq(0)
    expect(build(:build).pass_rate).to be_nil
  end

  describe "#duration_label" do
    { nil => "–", 0 => "<1s", 999 => "<1s", 1000 => "1.0s", 7_300 => "7.3s", 59_949 => "59.9s",
     60_000 => "1m 0s", 72_000 => "1m 12s" }.each do |ms, label|
      it "renders #{ms.inspect} as #{label}" do
        expect(build(:build, duration_ms: ms).duration_label).to eq(label)
      end
    end
  end

  describe "#ready_to_notify?" do
    it "needs a complete build whose runs are all analysed" do
      b = create(:build, project: project, expected_shards: 2)
      r1 = create(:run, project: project, build: b)
      expect(b).not_to be_ready_to_notify
      r2 = create(:run, project: project, build: b)
      expect(b).not_to be_ready_to_notify
      r1.update_column(:flakiness_analyzed_at, Time.current)
      expect(b).not_to be_ready_to_notify
      r2.update_column(:flakiness_analyzed_at, Time.current)
      expect(b).to be_ready_to_notify
    end

    it "agrees whether or not the runs are loaded" do
      b = create(:build, project: project, expected_shards: 1)
      r = create(:run, project: project, build: b)
      expect(Build.find(b.id).tap { |x| expect(x.runs).not_to be_loaded }).not_to be_ready_to_notify
      expect(Build.includes(:runs).find(b.id)).not_to be_ready_to_notify
      r.update_column(:flakiness_analyzed_at, Time.current)
      expect(Build.find(b.id)).to be_ready_to_notify
      expect(Build.includes(:runs).find(b.id)).to be_ready_to_notify
    end
  end

  describe "#complete?" do
    it "is true without expected shards" do
      expect(create(:build, expected_shards: nil)).to be_complete
    end

    it "is false until every expected shard has a run" do
      b = create(:build, project: project, expected_shards: 2)
      create(:run, project: project, build: b)
      expect(b).not_to be_complete
      create(:run, project: project, build: b)
      expect(b).to be_complete
    end
  end

  it "has no shard progress without expected shards" do
    expect(build(:build).shard_progress).to be_nil
  end

  it "requires a build_key unique per project" do
    create(:build, project: project, build_key: "k")
    expect(build(:build, project: project, build_key: "k")).not_to be_valid
    expect(build(:build, build_key: "k")).to be_valid
  end

  describe "#comparison_branch" do
    it "prefers the reported default branch, then the PR base" do
      expect(create(:build, project: project, branch: "f", default_branch: "trunk", pr_base_branch: "release").comparison_branch)
        .to eq("trunk")
      expect(create(:build, project: project, branch: "f", default_branch: "", pr_base_branch: "release").comparison_branch)
        .to eq("release")
    end

    it "falls back to main, then master, when the project has builds there, else nil" do
      lone = create(:build, project: project, branch: "feature")
      expect(lone.comparison_branch).to be_nil
      create(:build, project: project, branch: "master")
      expect(lone.reload.comparison_branch).to eq("master")
      create(:build, project: project, branch: "main")
      expect(lone.reload.comparison_branch).to eq("main")
    end

    it "memoizes, including a nil result, until reload" do
      lone = create(:build, project: project, branch: "feature")
      expect(lone.comparison_branch).to be_nil
      count = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| count += 1 unless p[:name] == "SCHEMA" }
      lone.comparison_branch
      ActiveSupport::Notifications.unsubscribe(sub)
      expect(count).to eq(0)
    end
  end
end
