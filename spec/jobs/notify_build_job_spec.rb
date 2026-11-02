require "rails_helper"

RSpec.describe NotifyBuildJob do
  let(:project) { create(:project) }
  let(:build) { create(:build, project: project, branch: "main", status: "failed") }

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  it "creates one pending delivery and enqueues delivery" do
    channel = create(:notification_channel, :slack, project: project)
    expect { described_class.perform_now(build.id) }
      .to change(NotificationDelivery, :count).by(1).and have_enqueued_job(DeliverNotificationJob).once
    expect(channel.notification_deliveries.last).to have_attributes(kind: "build", events: %w[failed], status: "pending", build: build)
  end

  it "is idempotent" do
    create(:notification_channel, :slack, project: project)
    expect { 2.times { described_class.perform_now(build.id) } }
      .to change(NotificationDelivery, :count).by(1).and have_enqueued_job(DeliverNotificationJob).once
  end

  it "skips disabled channels, other branches and empty events" do
    create(:notification_channel, :slack, project: project, enabled: false)
    create(:notification_channel, :teams, project: project, branch_filter: "pattern", branch_pattern: "release/*")
    create(:notification_channel, :email, project: project, on_failed: false)
    expect { described_class.perform_now(build.id) }.not_to change(NotificationDelivery, :count)
  end

  it "skips incomplete builds" do
    create(:notification_channel, :slack, project: project)
    incomplete = create(:build, project: project, status: "failed", expected_shards: 2)
    expect { described_class.perform_now(incomplete.id) }.not_to change(NotificationDelivery, :count)
  end

  it "creates a delivery per channel" do
    create(:notification_channel, :slack, project: project)
    create(:notification_channel, :teams, project: project)
    expect { described_class.perform_now(build.id) }.to change(NotificationDelivery, :count).by(2)
  end

  it "does nothing while a run is not yet analysed" do
    create(:notification_channel, :slack, project: project)
    build.update!(expected_shards: 2)
    create(:run, project: project, build: build, flakiness_analyzed_at: Time.current)
    create(:run, project: project, build: build)
    expect { described_class.perform_now(build.id) }.not_to change(NotificationDelivery, :count)
  end


  describe "re-run attempts" do
    let(:test_case) { create(:test_case, project: project) }
    let(:rerun_build) { create(:build, project: project, branch: "main", ci_run_key: "gh:o/r:7", status: "failed") }
    let!(:channel) { create(:notification_channel, :slack, project: project, on_recovered: true) }

    def add_run(attempt, status, at: Time.current)
      run = create(:run, project: project, build: rerun_build, branch: "main", attempt: attempt, status: status,
                         total_count: 1, failed_count: status == "failed" ? 1 : 0, passed_count: status == "passed" ? 1 : 0,
                         flakiness_analyzed_at: at)
      create(:test_result, run: run, test_case: test_case, status: status)
      run
    end

    before do
      add_run(1, "failed", at: 10.minutes.ago)
      rerun_build.recompute!
      described_class.perform_now(rerun_build.id, 1)
    end

    it "notifies attempt 2 once, keeping the attempt-1 delivery, and evaluates the gate for attempt 2" do
      add_run(2, "passed", at: 5.minutes.ago)
      rerun_build.recompute!
      allow(Builds::Gate).to receive(:evaluate!).and_call_original
      2.times { described_class.perform_now(rerun_build.id, 2) }
      expect(Builds::Gate).to have_received(:evaluate!).with(rerun_build, attempt: 2).at_least(:once)
      expect(channel.notification_deliveries.order(:attempt).pluck(:attempt)).to eq([ 1, 2 ])
      expect(channel.notification_deliveries.find_by(attempt: 2).events).to eq(%w[recovered])
      expect(rerun_build.reload.gate_attempt).to eq(2)
    end

    it "does nothing while the quiet period has not elapsed, and does not re-enqueue" do
      add_run(2, "passed")
      rerun_build.recompute!
      expect { described_class.perform_now(rerun_build.id, 2) }.not_to change(NotificationDelivery, :count)
      expect(described_class).not_to have_been_enqueued
    end

    it "assigns the baseline before the gate when attempt 1 never became ready" do
      rerun_build.update_columns(baseline_assigned_at: nil, gate_attempt: nil, gate_evaluated_at: nil)
      add_run(2, "passed", at: 5.minutes.ago)
      rerun_build.recompute!
      order = []
      allow(Builds::Baseline).to receive(:assign!).and_wrap_original { |m, *a| order << :baseline; m.call(*a) }
      allow(Builds::Gate).to receive(:evaluate!).and_wrap_original { |m, *a, **k| order << :gate; m.call(*a, **k) }
      described_class.perform_now(rerun_build.id, 2)
      expect(order.first(2)).to eq(%i[baseline gate])
      expect(rerun_build.reload.baseline_assigned_at).to be_present
    end

    it "updates counts but sends no second delivery for a late attempt-2 run" do
      add_run(2, "passed", at: 5.minutes.ago)
      rerun_build.recompute!
      described_class.perform_now(rerun_build.id, 2)
      other_case = create(:test_case, project: project)
      late = create(:run, project: project, build: rerun_build, branch: "main", attempt: 2, status: "passed",
                          total_count: 1, passed_count: 1, flakiness_analyzed_at: 5.minutes.ago)
      create(:test_result, run: late, test_case: other_case, status: "passed")
      rerun_build.recompute!
      expect { described_class.perform_now(rerun_build.id, 2) }.not_to change(NotificationDelivery, :count)
      expect(rerun_build.reload.total_count).to eq(2)
      expect(channel.notification_deliveries.where(attempt: 2).count).to eq(1)
    end

    it "logs a run that arrives after its attempt was announced" do
      add_run(2, "passed", at: 5.minutes.ago)
      rerun_build.recompute!
      described_class.perform_now(rerun_build.id, 2)
      allow(Rails.logger).to receive(:info)
      described_class.perform_now(rerun_build.id, 2)
      expect(Rails.logger).to have_received(:info)
        .with("[notify] build #{rerun_build.id} attempt 2: late run after announcement, no new delivery")
    end
  end

  describe "attempt 2 of a build without a ci_run_key (Azure) or without attempt 1" do
    it "follows the ordinary first-attempt flow with its own attempt number" do
      create(:notification_channel, :slack, project: project)
      azure = create(:build, project: project, branch: "main", status: "failed")
      create(:run, project: project, build: azure, attempt: 2, flakiness_analyzed_at: Time.current)
      expect { described_class.perform_now(azure.id, 2) }.to change(NotificationDelivery, :count).by(1)
      expect(NotificationDelivery.last.attempt).to eq(2)
    end

    it "does the same for a GitHub build whose attempt 1 never uploaded" do
      create(:notification_channel, :slack, project: project)
      gh = create(:build, project: project, branch: "main", status: "failed", ci_run_key: "gh:o/r:9")
      create(:run, project: project, build: gh, attempt: 2, flakiness_analyzed_at: Time.current)
      expect { described_class.perform_now(gh.id, 2) }.to change(NotificationDelivery, :count).by(1)
      expect(NotificationDelivery.last.attempt).to eq(2)
    end
  end
end
