require "rails_helper"

RSpec.describe Notifications::EmailNotifier do
  let(:channel) { create(:notification_channel, :email, recipients: "a@example.com\nb@example.com") }
  let(:message) do
    Notifications::Message.new(title: "Raider: build failed — Shop", headline: "build failed",
                               summary: "1 failed", project_name: "Shop", branch: "main", commit: nil,
                               failures: [], new_flaky: [], pass_rate: nil,
                               build_url: "http://example.com/b", pr_url: nil)
  end

  it "delivers via the mailer" do
    expect { described_class.new(channel).deliver(message) }.to change { ActionMailer::Base.deliveries.size }.by(1)
  end

  it "maps mail errors to retryable" do
    allow(NotificationMailer).to receive(:build_notification).and_raise(SocketError, "boom")
    expect { described_class.new(channel).deliver(message) }.to raise_error(Notifications::RetryableError)
  end

  [ Net::ReadTimeout.new, Net::SMTPAuthenticationError.new("535 bad") ].each do |error|
    it "maps #{error.class} to retryable" do
      allow(NotificationMailer).to receive(:build_notification).and_raise(error)
      expect { described_class.new(channel).deliver(message) }.to raise_error(Notifications::RetryableError)
    end
  end

  it "is returned by the factory" do
    expect(Notifications.notifier_for(channel)).to be_a(described_class)
    expect(Notifications.notifier_for(create(:notification_channel, :slack))).to be_a(Notifications::SlackNotifier)
    expect(Notifications.notifier_for(create(:notification_channel, :teams))).to be_a(Notifications::TeamsNotifier)
  end
end
