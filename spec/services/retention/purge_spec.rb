require "rails_helper"

RSpec.describe Retention::Purge do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-20 03:30 UTC") }
  let(:config) { Retention::Config.new(attachment_days: 30, result_days: 90) }
  let(:purge) { described_class.new(config: config, pause: 0) }
  let(:project) { create(:project) }

  def run_aged(days, **attrs)
    travel_to(now - days.days) { create(:run, project: project, **attrs) }
  end

  def result_with_screenshot(run, status: "failed")
    result = create(:test_result, run: run, status: status)
    result.attachments.attach(io: StringIO.new("png"), filename: "shot.png", content_type: "image/png")
    result
  end

  def blob_path(blob)
    ActiveStorage::Blob.service.path_for(blob.key)
  end

  it "keeps attachments of a 29-day run and purges those of a 31-day run" do
    fresh = result_with_screenshot(run_aged(29))
    stale = result_with_screenshot(run_aged(31))
    stale_path = blob_path(stale.attachments.first.blob)

    report = purge.call(now: now)

    expect(fresh.reload.attachments).to be_attached
    expect(stale.reload.attachments).not_to be_attached
    expect(File.exist?(stale_path)).to be(false)
    expect(stale.run.reload.attachments_purged_at).to eq(now)
    expect(fresh.run.reload.attachments_purged_at).to be_nil
    expect(stale.reload).to be_present # the result itself is kept until 90 days
    expect(report.attachments).to eq(1)
  end

  it "keeps results of an 89-day run and deletes those of a 91-day run, leaving counts" do
    kept_run = run_aged(89)
    create(:test_result, run: kept_run)
    old_run = run_aged(91, total_count: 3, passed_count: 2, failed_count: 1)
    old_run.build.update!(total_count: 3, passed_count: 2, failed_count: 1)
    create_list(:test_result, 3, run: old_run)

    report = purge.call(now: now)

    expect(kept_run.test_results.count).to eq(1)
    expect(old_run.test_results.count).to eq(0)
    expect(old_run.reload).to have_attributes(results_purged_at: now, total_count: 3, passed_count: 2, failed_count: 1)
    expect(old_run.build.reload).to have_attributes(total_count: 3, passed_count: 2, failed_count: 1)
    expect(report.results).to eq(3)
  end

  it "purges a 95-day run's attachments and results in one call" do
    result = result_with_screenshot(run_aged(95))
    path = blob_path(result.attachments.first.blob)

    purge.call(now: now)

    expect(File.exist?(path)).to be(false)
    expect(ActiveStorage::Attachment.count).to eq(0)
    expect(ActiveStorage::Blob.count).to eq(0)
    expect(result.run.reload).to have_attributes(attachments_purged_at: now, results_purged_at: now)
  end

  it "purges a build's shards independently by their own age" do
    build = create(:build, project: project)
    old_shard = travel_to(now - 91.days) { create(:run, project: project, build: build) }
    new_shard = travel_to(now - 10.days) { create(:run, project: project, build: build) }
    create(:test_result, run: old_shard)
    create(:test_result, run: new_shard)

    purge.call(now: now)

    expect(old_shard.reload.results_purged_at).to eq(now)
    expect(new_shard.reload.results_purged_at).to be_nil
    expect(new_shard.test_results.count).to eq(1)
  end

  it "deletes error groups and test cases left without results, with their verdicts" do
    old_run = run_aged(91)
    group = travel_to(now - 91.days) { create(:error_group, project: project) }
    orphan_case = travel_to(now - 91.days) { create(:test_case, project: project) }
    create(:test_result, run: old_run, test_case: orphan_case, status: "failed", error_group: group)
    create(:test_case_verdict, test_case: orphan_case)
    living_case = travel_to(now - 91.days) { create(:test_case, project: project) }
    create(:test_result, run: old_run, test_case: living_case)
    create(:test_result, run: run_aged(1), test_case: living_case)

    report = purge.call(now: now)

    expect(ErrorGroup.exists?(group.id)).to be(false)
    expect(TestCase.exists?(orphan_case.id)).to be(false)
    expect(TestCaseVerdict.where(test_case_id: orphan_case.id)).to be_empty
    expect(TestCase.exists?(living_case.id)).to be(true)
    expect(report).to have_attributes(error_groups: 1, test_cases: 1)
  end

  it "keeps result-less test cases that have a quarantine, active or released, with their events" do
    user = create(:user)
    active_case = travel_to(now - 91.days) { create(:test_case, project: project) }
    released_case = travel_to(now - 91.days) { create(:test_case, project: project) }
    bare_case = travel_to(now - 91.days) { create(:test_case, project: project) }
    active = travel_to(now - 91.days) do
      Quarantine.quarantine!(test_case: active_case, user: user, reason: "flaky", days: 30)
    end
    released = travel_to(now - 91.days) do
      Quarantine.quarantine!(test_case: released_case, user: user, reason: "flaky", days: 7).release!(user: user)
    end

    report = purge.call(now: now)

    expect(TestCase.where(id: [ active_case.id, released_case.id ]).count).to eq(2)
    expect(TestCase.exists?(bare_case.id)).to be(false)
    expect(Quarantine.where(id: [ active.id, released.id ]).count).to eq(2)
    expect(QuarantineEvent.where(quarantine_id: active.id).count).to eq(1)
    expect(QuarantineEvent.where(quarantine_id: released.id).count).to eq(2)
    expect(report.test_cases).to eq(1)
  end

  it "keeps a recently created test case and a recently seen error group that have no results yet" do
    fresh_case = create(:test_case, project: project)
    fresh_group = create(:error_group, project: project)

    purge.call(now: now)

    expect(TestCase.exists?(fresh_case.id)).to be(true)
    expect(ErrorGroup.exists?(fresh_group.id)).to be(true)
  end

  it "does nothing on a second call" do
    result_with_screenshot(run_aged(95))
    purge.call(now: now)

    expect(purge.call(now: now).to_h.values).to all(eq(0))
  end

  it "counts without changing anything on a dry run" do
    result_with_screenshot(run_aged(31))
    result_with_screenshot(run_aged(95))

    report = purge.call(now: now, dry_run: true)

    expect(report).to have_attributes(runs: 2, attachments: 2, results: 1)
    expect(ActiveStorage::Attachment.count).to eq(2)
    expect(TestResult.count).to eq(2)
    expect(Run.where.not(attachments_purged_at: nil)).to be_empty
  end

  it "leaves a run unmarked and its rows and file in place when a file delete fails" do
    result = result_with_screenshot(run_aged(31))
    path = blob_path(result.attachments.first.blob)
    allow(ActiveStorage::Blob.service).to receive(:delete).and_raise(Errno::EACCES)

    expect { purge.call(now: now) }.to raise_error(Errno::EACCES)
    expect(ActiveStorage::Attachment.count).to eq(1)
    expect(File.exist?(path)).to be(true)
    expect(result.run.reload.attachments_purged_at).to be_nil
  end

  it "deletes all results of one run that spans several batches and marks the run" do
    stub_const("Retention::Purge::BATCH_SIZE", 1)
    run = run_aged(91)
    create_list(:test_result, 3, run: run)

    expect(purge.call(now: now).results).to eq(3)
    expect(run.test_results.count).to eq(0)
    expect(run.reload.results_purged_at).to eq(now)
  end

  it "works in batches and sleeps between them" do
    stub_const("Retention::Purge::BATCH_SIZE", 1)
    2.times { create(:test_result, run: run_aged(91)) }
    sleeper = described_class.new(config: config, pause: 0.25)
    allow(sleeper).to receive(:sleep)

    expect(sleeper.call(now: now).results).to eq(2)
    expect(sleeper).to have_received(:sleep).with(0.25).at_least(:once)
  end

  it "formats the report as one log line" do
    report = Retention::Report.new(runs: 1, results: 2, attachments: 3, error_groups: 4, test_cases: 5)
    expect(report.to_s).to eq("runs=1 results=2 attachments=3 error_groups=4 test_cases=5")
  end
end
