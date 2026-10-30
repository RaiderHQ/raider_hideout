require "rails_helper"

RSpec.describe Builds::GateReport do
  let(:build) { create(:build) }

  def report = described_class.new(build.reload)

  it "is pending while the verdict is null" do
    expect(report.state).to eq("pending")
    expect(report).not_to be_evaluated
    expect(report.rules).to eq([])
  end

  [ nil, "", "not json", "null", "[1]", '{"rules":[1]}', '{"rules":{"pass_rate":"x"}}' ].each do |text|
    it "reads stored #{text.inspect} as no rules without raising" do
      build.update_columns(gate_status: "failed", gate_result: text, gate_evaluated_at: Time.current)
      expect(report.rules).to eq([])
      expect(report.failed_rules).to eq([])
    end
  end

  it "parses the stored verdict once per report" do
    build.update_columns(gate_status: "failed", gate_evaluated_at: Time.current,
                         gate_result: JSON.generate("rules" => { "new_flaky" => { "count" => 1, "outcome" => "failed" } }))
    subject = report
    allow(JSON).to receive(:parse).and_call_original

    3.times { subject.rules && subject.failed_rules }

    expect(subject.failed_rules.map(&:rule)).to eq(%w[new_flaky])
    expect(JSON).to have_received(:parse).once
  end
end
