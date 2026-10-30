require "rails_helper"

RSpec.describe RetentionJob do
  it "runs the purge and logs the report as one line" do
    report = Retention::Report.new(runs: 1, results: 2, attachments: 3, error_groups: 0, test_cases: 0)
    allow(Retention::Purge).to receive(:new).and_return(instance_double(Retention::Purge, call: report))
    allow(Rails.logger).to receive(:info)

    described_class.perform_now

    expect(Rails.logger).to have_received(:info).with("[retention] runs=1 results=2 attachments=3 error_groups=0 test_cases=0")
  end
end
