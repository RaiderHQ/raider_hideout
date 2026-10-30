require "rails_helper"

RSpec.describe Builds::Baseline do
  let(:project) { create(:project) }

  def make_build(branch: "main", at: Time.current, shards: nil, runs: 1, **attrs)
    build = create(:build, project: project, branch: branch, created_at: at, expected_shards: shards, **attrs)
    runs.times { create(:run, project: project, build: build, branch: branch) }
    build
  end

  it "picks the latest complete build on the comparison branch created before the build" do
    make_build(at: 3.hours.ago)
    expected = make_build(at: 2.hours.ago)
    make_build(at: 1.minute.from_now)
    build = make_build(branch: "feature", at: 1.hour.ago, default_branch: "main")
    described_class.assign!(build)
    expect(build.reload).to have_attributes(baseline_build_id: expected.id, baseline_assigned_at: be_present)
  end

  it "skips synthetic candidates for a CI build" do
    ci = make_build(at: 3.hours.ago)
    make_build(at: 2.hours.ago, build_key: "run:abc")
    build = make_build(branch: "feature", at: 1.hour.ago, default_branch: "main")
    described_class.assign!(build)
    expect(build.reload.baseline_build_id).to eq(ci.id)
  end

  it "lets a synthetic build pick synthetic or CI candidates" do
    make_build(at: 3.hours.ago)
    synthetic = make_build(at: 2.hours.ago, build_key: "run:abc")
    build = make_build(branch: "feature", at: 1.hour.ago, default_branch: "main", build_key: "run:def")
    described_class.assign!(build)
    expect(build.reload.baseline_build_id).to eq(synthetic.id)
  end

  it "skips an incomplete candidate" do
    complete = make_build(at: 3.hours.ago)
    make_build(at: 2.hours.ago, shards: 2, runs: 1)
    build = make_build(branch: "feature", at: 1.hour.ago, default_branch: "main")
    described_class.assign!(build)
    expect(build.reload.baseline_build_id).to eq(complete.id)
  end

  it "ignores other branches" do
    make_build(branch: "develop", at: 2.hours.ago)
    build = make_build(branch: "feature", at: 1.hour.ago, default_branch: "main")
    described_class.assign!(build)
    expect(build.reload).to have_attributes(baseline_build_id: nil, baseline_assigned_at: be_present)
  end

  it "compares a default-branch build with the previous one, never itself" do
    previous = make_build(at: 2.hours.ago)
    build = make_build(at: 1.hour.ago, default_branch: "main")
    described_class.assign!(build)
    expect(build.reload.baseline_build_id).to eq(previous.id)
  end

  it "records the lookup when the first build has nothing to compare with" do
    build = make_build(default_branch: "main")
    described_class.assign!(build)
    expect(build.reload).to have_attributes(baseline_build_id: nil, baseline_assigned_at: be_present)
  end

  it "records the lookup when there is no comparison branch" do
    build = make_build(branch: nil)
    expect(described_class.assign!(build)).to be_nil
    expect(build.reload).to have_attributes(baseline_build_id: nil, baseline_assigned_at: be_present)
  end

  it "assigns once: a newer main build does not move the baseline" do
    first = make_build(at: 3.hours.ago)
    build = make_build(branch: "feature", at: 2.hours.ago, default_branch: "main")
    described_class.assign!(build)
    make_build(at: 1.hour.ago)
    described_class.assign!(build)
    expect(build.reload.baseline_build_id).to eq(first.id)
  end

  it "breaks a created_at tie by the lower id" do
    at = 1.hour.ago.change(usec: 0)
    make_build(at: at)
    higher = make_build(at: at)
    build = make_build(branch: "feature", at: at, default_branch: "main")
    described_class.assign!(build)
    expect(build.reload.baseline_build_id).to eq(higher.id)
  end

  it "scans only 50 candidates" do
    make_build(at: 100.hours.ago)
    50.times { |i| make_build(at: (50 - i).hours.ago, shards: 2, runs: 1) }
    build = make_build(branch: "feature", at: 1.minute.ago, default_branch: "main")
    described_class.assign!(build)
    expect(build.reload.baseline_build_id).to be_nil
  end

  it "excludes a same-created_at candidate with a higher id" do
    at = 1.hour.ago.change(usec: 0)
    build = make_build(branch: "feature", at: at, default_branch: "main")
    make_build(at: at)
    described_class.assign!(build)
    expect(build.reload.baseline_build_id).to be_nil
  end

  it "lets the first of two stale instances win" do
    first = make_build(at: 3.hours.ago)
    build = make_build(branch: "feature", at: 2.hours.ago, default_branch: "main")
    stale_a = Build.find(build.id)
    stale_b = Build.find(build.id)
    described_class.assign!(stale_a)
    newer = make_build(at: 1.hour.ago)
    newer.update_column(:created_at, 90.minutes.ago)
    described_class.assign!(stale_b)
    expect(build.reload.baseline_build_id).to eq(first.id)
    expect(stale_b.baseline_build_id).to eq(first.id)
  end

  it "nullifies the baseline when its build is deleted, leaving the comparison unavailable" do
    baseline = make_build(at: 2.hours.ago)
    build = make_build(branch: "feature", at: 1.hour.ago, default_branch: "main")
    described_class.assign!(build)
    baseline.destroy
    comparison = Builds::Comparison.new(build.reload)
    expect(build.baseline_build_id).to be_nil
    expect(comparison).not_to be_available
    expect(comparison.new_failures).to eq([])
  end

  it "skips builds with expired results" do
    expired = make_build(at: 2.days.ago)
    expired.runs.each { |run| run.update_columns(results_purged_at: 1.day.ago) }
    build = make_build(branch: "feature", at: 1.hour.ago, default_branch: "main")

    described_class.assign!(build)

    expect(build.reload.baseline_build_id).to be_nil
  end
end
