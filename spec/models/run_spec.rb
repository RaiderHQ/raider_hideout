require "rails_helper"

RSpec.describe Run do
  it "computes pass rate from passed, failed and quarantined only" do
    expect(build(:run, passed_count: 3, failed_count: 1, skipped_count: 10).pass_rate).to eq(75)
    expect(build(:run, passed_count: 1, failed_count: 1, quarantined_count: 2).pass_rate).to eq(25)
    expect(build(:run, passed_count: 0, failed_count: 0).pass_rate).to be_nil
  end

  it "stores named attachments on results" do
    result = create(:test_result)
    result.attachments.attach(io: StringIO.new("PNG"), filename: "shot.png", content_type: "image/png",
                              metadata: { "name" => "screenshot" })
    expect(result.attachment_name(result.attachments.first)).to eq("screenshot")
  end
end
