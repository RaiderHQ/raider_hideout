require "rails_helper"

RSpec.describe Retention::Config do
  it "defaults to 30 attachment days and 90 result days" do
    expect(described_class.from({})).to have_attributes(attachment_days: 30, result_days: 90)
  end

  it "reads overrides and ignores surrounding whitespace" do
    config = described_class.from("RETENTION_ATTACHMENT_DAYS" => " 7 ", "RETENTION_RESULT_DAYS" => "14")
    expect(config).to have_attributes(attachment_days: 7, result_days: 14)
  end

  it "treats a blank value as the default" do
    expect(described_class.from("RETENTION_RESULT_DAYS" => "  ").result_days).to eq(90)
  end

  [ "0", "-3", "abc", "1.5", "30d" ].each do |raw|
    it "rejects #{raw.inspect}, naming the variable" do
      expect { described_class.from("RETENTION_RESULT_DAYS" => raw) }
        .to raise_error(ArgumentError, /RETENTION_RESULT_DAYS must be a whole number of days, at least 1/)
    end
  end

  it "rejects attachment days longer than result days" do
    expect { described_class.from("RETENTION_ATTACHMENT_DAYS" => "100", "RETENTION_RESULT_DAYS" => "90") }
      .to raise_error(ArgumentError, "RETENTION_ATTACHMENT_DAYS (100) must not exceed RETENTION_RESULT_DAYS (90)")
  end

  it "is exposed as Retention.config" do
    expect(Retention.config).to be_a(described_class)
  end
end
