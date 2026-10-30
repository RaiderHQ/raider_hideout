require "rails_helper"

RSpec.describe ExpireQuarantinesJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  def quarantine(days:)
    Quarantine.quarantine!(test_case: create(:test_case), user: user, reason: "flaky", days: days)
  end

  it "writes one expired event per expired, unreleased quarantine, and is idempotent" do
    short = quarantine(days: 7)
    long = quarantine(days: 30)
    released = quarantine(days: 7)
    released.release!(user: user)

    travel_to(8.days.from_now) do
      2.times { described_class.perform_now }
    end

    expect(short.events.where(action: "expired").pluck(:actor_id, :expires_at)).to eq([ [ nil, short.expires_at ] ])
    expect(long.events.where(action: "expired")).to be_empty
    expect(released.events.where(action: "expired")).to be_empty
  end

  it "is scheduled nightly at 03:45" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "expire_quarantines")
    expect(schedule).to eq("class" => "ExpireQuarantinesJob", "schedule" => "at 3:45am every day")
  end
end
