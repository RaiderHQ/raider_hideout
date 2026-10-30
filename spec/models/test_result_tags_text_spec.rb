require "rails_helper"

RSpec.describe TestResult, ".tags_text_for" do
  it "lowercases, strips, drops | and duplicates, and wraps in |" do
    expect(described_class.tags_text_for([ "Smoke", " login ", "a|b", "smoke", "slow test" ])).to eq("|smoke|login|ab|slow test|")
  end

  it "is empty for no tags or only blank tags" do
    expect(described_class.tags_text_for([])).to eq("")
    expect(described_class.tags_text_for(nil)).to eq("")
    expect(described_class.tags_text_for([ " ", "|" ])).to eq("")
  end

  it "normalizes one tag the same way" do
    expect(described_class.normalize_tag(" Sm|oke ")).to eq("smoke")
  end
end
