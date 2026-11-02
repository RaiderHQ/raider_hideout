require "rails_helper"

RSpec.describe BuildRerun do
  let(:build_record) { create(:build) }

  def rerun(**attrs) = build_record.reruns.create!({ attempt_before: 1, status: "pending" }.merge(attrs))

  it "words each status" do
    expect(rerun.outcome_copy).to eq("waiting for GitHub")
    expect(rerun(status: "accepted", http_status: 201).outcome_copy).to eq("GitHub accepted")
    expect(rerun(status: "rejected", http_status: 403).outcome_copy).to eq(Builds::Rerun::COPY.fetch(403))
    expect(rerun(status: "failed", http_status: 500).outcome_copy).to eq(Builds::Rerun::BUSY)
    expect(rerun(status: "failed", http_status: nil).outcome_copy).to eq(Builds::Rerun::NETWORK)
  end

  it "names a deleted user someone and formats the clock as HH:MM" do
    record = rerun(user: nil, created_at: Time.zone.local(2026, 11, 2, 9, 5))
    expect(record.starter_label).to eq("someone")
    expect(record.clock).to eq("09:05")
  end
end
