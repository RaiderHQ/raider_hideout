require "rails_helper"

RSpec.describe Notifications::BranchFilter do
  def match?(filter, branch, default_branch: nil, pattern: nil)
    channel = build(:notification_channel, branch_filter: filter, branch_pattern: pattern)
    described_class.match?(channel, build(:build, branch: branch, default_branch: default_branch))
  end

  it "matches the build's default branch" do
    expect(match?("default", "develop", default_branch: "develop")).to be(true)
  end

  it "does not match main when default_branch is develop" do
    expect(match?("default", "main", default_branch: "develop")).to be(false)
  end

  it "falls back to main/master without a default_branch" do
    expect(match?("default", "master")).to be(true)
    expect(match?("default", "feature/x")).to be(false)
  end

  it "matches any branch, even nil, with all" do
    expect(match?("all", nil)).to be(true)
  end

  it "never matches a nil branch with default or pattern" do
    expect(match?("default", nil)).to be(false)
    expect(match?("pattern", nil, pattern: "*")).to be(false)
  end

  it "treats / as a path separator in patterns" do
    expect(match?("pattern", "release/1.2", pattern: "release/*")).to be(true)
    expect(match?("pattern", "release/1.2/hotfix", pattern: "release/*")).to be(false)
    expect(match?("pattern", "main", pattern: "release/*")).to be(false)
  end
end
