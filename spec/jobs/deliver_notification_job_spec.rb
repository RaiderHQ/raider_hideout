require "rails_helper"

RSpec.describe DeliverNotificationJob do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  def drain_jobs
    perform_enqueued_jobs while enqueued_jobs.any?
  end

  let(:channel) { create(:notification_channel, webhook_url: "https://hooks.slack.com/services/T/B/secretXYZ") }
  let(:delivery) { create(:notification_delivery, notification_channel: channel) }
  let(:notifier) { instance_double(Notifications::SlackNotifier, deliver: nil) }

  before { allow(Notifications).to receive(:notifier_for).and_return(notifier) }

  it "marks sent on success" do
    described_class.perform_now(delivery.id)
    delivery.reload
    expect(delivery).to have_attributes(status: "sent", attempts: 1, last_error: nil)
    expect(delivery.sent_at).to be_present
  end

  it "fails permanently with a redacted error and no retry" do
    allow(notifier).to receive(:deliver).and_raise(Notifications::PermanentError, "HTTP 404 #{channel.webhook_url}")
    expect { described_class.perform_now(delivery.id) }.not_to have_enqueued_job(described_class)
    delivery.reload
    expect(delivery.status).to eq("failed")
    expect(delivery.last_error).not_to include("secretXYZ")
    expect(delivery.last_error).to include("hooks.slack.com/…/tXYZ")
  end

  it "keeps pending and re-enqueues on a retryable error" do
    allow(notifier).to receive(:deliver).and_raise(Notifications::RetryableError, "HTTP 500")
    expect { described_class.perform_now(delivery.id) }.to have_enqueued_job(described_class)
    expect(delivery.reload).to have_attributes(status: "pending", last_error: "HTTP 500", attempts: 1)
  end

  it "fails after 5 executions" do
    allow(notifier).to receive(:deliver).and_raise(Notifications::RetryableError, "HTTP 500 #{channel.webhook_url}")
    described_class.perform_later(delivery.id)
    drain_jobs
    delivery.reload
    expect(delivery.status).to eq("failed")
    expect(delivery.attempts).to eq(5)
    expect(delivery.last_error).not_to include("secretXYZ")
    expect(notifier).to have_received(:deliver).exactly(5).times
    expect(enqueued_jobs).to be_empty
  end

  it "honors Retry-After within the same budget" do
    allow(notifier).to receive(:deliver).and_raise(Notifications::RetryableError.new("HTTP 429", retry_after: 42))
    travel_to(Time.zone.local(2026, 1, 1)) do
      expect { described_class.perform_now(delivery.id) }
        .to have_enqueued_job(described_class).at(42.seconds.from_now)
    end
    expect(delivery.reload.status).to eq("pending")
  end

  it "counts Retry-After retries toward the 5 attempts" do
    allow(notifier).to receive(:deliver).and_raise(Notifications::RetryableError.new("HTTP 429", retry_after: 1))
    described_class.perform_later(delivery.id)
    drain_jobs
    expect(delivery.reload).to have_attributes(status: "failed", attempts: 5)
    expect(notifier).to have_received(:deliver).exactly(5).times
  end

  it "skips an already sent delivery" do
    delivery.update!(status: "sent")
    described_class.perform_now(delivery.id)
    expect(Notifications).not_to have_received(:notifier_for)
  end

  it "fails when the channel is disabled" do
    channel.update!(enabled: false)
    described_class.perform_now(delivery.id)
    expect(delivery.reload).to have_attributes(status: "failed", last_error: "channel disabled")
    expect(Notifications).not_to have_received(:notifier_for)
  end

  it "ignores a missing delivery" do
    expect { described_class.perform_now(0) }.not_to raise_error
  end

  it "sends a test message for test deliveries" do
    test_delivery = create(:notification_delivery, notification_channel: channel, kind: "test", build: nil, events: [])
    options = Rails.application.config.action_mailer.default_url_options || {}
    allow(Notifications::Message).to receive(:test).and_call_original
    described_class.perform_now(test_delivery.id)
    expect(Notifications::Message).to have_received(:test).with(channel, url_options: options)
    expect(test_delivery.reload.status).to eq("sent")
  end

  it "marks failed and re-raises on unexpected errors, redacted" do
    allow(notifier).to receive(:deliver).and_raise(RuntimeError, "boom #{channel.webhook_url}")
    expect { described_class.perform_now(delivery.id) }.to raise_error(RuntimeError)
    delivery.reload
    expect(delivery.status).to eq("failed")
    expect(delivery.last_error).to start_with("unexpected RuntimeError")
    expect(delivery.last_error).not_to include("secretXYZ")
  end

  it "fails the delivery when the channel is gone" do
    id = delivery.id
    allow_any_instance_of(NotificationDelivery).to receive(:notification_channel).and_return(nil) # rubocop:disable RSpec/AnyInstance
    described_class.perform_now(id)
    expect(NotificationDelivery.find(id)).to have_attributes(status: "failed", last_error: "channel deleted")
  end

  it "fails on retry when the channel was disabled in between" do
    allow(notifier).to receive(:deliver).and_raise(Notifications::RetryableError, "HTTP 500")
    described_class.perform_later(delivery.id)
    perform_enqueued_jobs(only: described_class)
    channel.update!(enabled: false)
    drain_jobs
    expect(delivery.reload).to have_attributes(status: "failed", last_error: "channel disabled")
    expect(notifier).to have_received(:deliver).once
  end

  it "perform_now swallows a retryable error and leaves a pending delivery (what Send test sees)" do
    allow(notifier).to receive(:deliver).and_raise(Notifications::RetryableError, "HTTP 500")
    expect { described_class.perform_now(delivery.id) }.not_to raise_error
    expect(delivery.reload).to have_attributes(status: "pending", last_error: "HTTP 500")
    expect(enqueued_jobs.count { |j| j["job_class"] == "DeliverNotificationJob" }).to eq(1)
  end

  context "with an email channel and no SMTP" do
    include LogCapture

    let(:channel) { create(:notification_channel, kind: "email", webhook_url: nil, recipients: "a@example.com") }

    it "skips the delivery and says why" do
      mail_disabled!
      log = capture_log { described_class.perform_now(delivery.id) }
      expect(delivery.reload).to have_attributes(status: "failed", last_error: "skipped: SMTP_ADDRESS not set")
      expect(ActionMailer::Base.deliveries).to be_empty
      expect(log).to include("[hideout] email channel #{delivery.notification_channel_id} skipped: SMTP_ADDRESS not set")
    end
  end
end
