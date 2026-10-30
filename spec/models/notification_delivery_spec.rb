require "rails_helper"

RSpec.describe NotificationDelivery do
  it "allows only one build delivery per channel and build" do
    delivery = create(:notification_delivery)
    expect {
      described_class.create!(notification_channel: delivery.notification_channel, build: delivery.build, kind: "build")
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "allows many test deliveries without a build" do
    channel = create(:notification_channel)
    2.times { described_class.create!(notification_channel: channel, build: nil, kind: "test") }
    expect(channel.notification_deliveries.count).to eq(2)
  end

  it "is removed when its build or project is destroyed" do
    delivery = create(:notification_delivery)
    expect { delivery.build.destroy }.to change(described_class, :count).by(-1)
    other = create(:notification_delivery)
    expect { other.notification_channel.project.destroy }.to change(described_class, :count).by(-1)
    expect(NotificationChannel.where(id: other.notification_channel_id)).to be_empty
  end

  it "stores events as an array and defaults to pending" do
    delivery = create(:notification_delivery, events: %w[failed new_flaky])
    expect(delivery.reload.events).to eq(%w[failed new_flaky])
    expect(delivery.status).to eq("pending")
    expect(delivery.attempts).to eq(0)
  end
end
