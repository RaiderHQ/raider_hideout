require "rails_helper"

RSpec.describe Github::Repository do
  def parse(key) = described_class.from_build(Build.new(ci_run_key: key))

  it "parses a valid key" do
    expect(parse("github_actions:RaiderHQ/raider_hideout:123456")).to eq([ "RaiderHQ", "raider_hideout", "123456" ])
    expect(parse("github_actions:a.b-c/d_e.f:1")).to eq([ "a.b-c", "d_e.f", "1" ])
  end

  it "rejects hostile or malformed keys" do
    [ "github_actions:../repo:1", "github_actions:owner/..:1", "github_actions:./repo:1", "github_actions:owner/.:1",
      "github_actions:a%2Fb/repo:1", "github_actions:a b/repo:1", "github_actions:o/r:#{'1' * 21}",
      "github_actions:o/r:12x", "github_actions:o/r", "github_actions:o/r/x:1", "gitlab:o/r:1",
      "github_actions:o/r:1\n", "github_actions:#{'a' * 101}/r:1", nil, "" ].each do |key|
      expect(parse(key)).to be_nil, key.inspect
    end
  end
end
