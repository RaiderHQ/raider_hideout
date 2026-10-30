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
end
