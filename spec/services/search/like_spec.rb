require "rails_helper"

RSpec.describe Search::Like do
  it "escapes LIKE wildcards and the escape character" do
    expect(described_class.escape(%q(100%_a\b))).to eq(%q(100\%\_a\\\\b))
  end

  it "leaves other text alone" do
    expect(described_class.escape("Net::ReadTimeout")).to eq("Net::ReadTimeout")
  end
end
