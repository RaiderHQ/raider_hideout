require "rails_helper"
require Rails.root.join("db/migrate/20261024150000_add_gate_verdict_to_builds").to_s

RSpec.describe "gate verdict backfill" do
  it "marks every build without a verdict as none and leaves evaluated builds alone" do
    old = create(:build)
    evaluated = create(:build)
    evaluated.update_columns(gate_status: "failed", gate_result: '{"rules":{}}', gate_evaluated_at: 1.hour.ago)
    now = Time.zone.parse("2026-10-24 12:00:00")

    AddGateVerdictToBuilds::Backfill.call(now: now)

    expect(old.reload).to have_attributes(gate_status: "none", gate_result: '{"rules":{}}', gate_evaluated_at: now)
    expect(evaluated.reload.gate_status).to eq("failed")
  end
end
