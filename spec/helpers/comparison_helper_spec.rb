require "rails_helper"

RSpec.describe ComparisonHelper, type: :helper do
  FakeVerdict = Struct.new(:flaky, :source)

  let(:comparison) { instance_double(Builds::Comparison) }

  def tag(verdicts: {}, status: nil)
    allow(comparison).to receive(:status_for).with(1).and_return(status)
    helper.failure_tag(1, comparison, verdicts, "main")
  end

  it "prefers Flaky from the own branch over everything" do
    expect(tag(verdicts: { 1 => FakeVerdict.new(true, :branch) }, status: :new_failure)).to eq([ "Flaky", :flaky ])
  end

  it "uses the default branch name when the verdict is inherited" do
    expect(tag(verdicts: { 1 => FakeVerdict.new(true, :default_branch) }, status: :still_failing)).to eq([ "Flaky on main", :flaky ])
  end

  it "falls through a non-flaky verdict to New, then Still failing" do
    verdicts = { 1 => FakeVerdict.new(false, :branch) }
    expect(tag(verdicts: verdicts, status: :new_failure)).to eq([ "New", :new ])
    expect(tag(verdicts: verdicts, status: :still_failing)).to eq([ "Still failing", :still_failing ])
  end

  it "is nil with no verdict and no status, or without a comparison" do
    expect(tag).to be_nil
    expect(helper.failure_tag(1, nil, {}, "main")).to be_nil
  end
end
