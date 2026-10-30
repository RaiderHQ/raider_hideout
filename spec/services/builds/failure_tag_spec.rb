require "rails_helper"

RSpec.describe Builds::FailureTag do
  let(:comparison) { instance_double(Builds::Comparison, status_for: :new_failure) }

  def verdict(flaky:, source:) = Verdict.new(flaky: flaky, reason: nil, flip_rate: nil, source: source)
  def tag(verdict, comparison = self.comparison) = described_class.for(1, comparison, { 1 => verdict }, "main")

  it "puts own-branch flaky first, then default-branch flaky, then new, then still failing, then none" do
    expect(tag(verdict(flaky: true, source: :branch))).to eq([ "Flaky", :flaky ])
    expect(tag(verdict(flaky: true, source: :default_branch))).to eq([ "Flaky on main", :flaky ])
    expect(tag(verdict(flaky: false, source: :branch))).to eq([ "New", :new ])
    still = instance_double(Builds::Comparison, status_for: :still_failing)
    expect(tag(Verdict::NONE, still)).to eq([ "Still failing", :still_failing ])
    expect(tag(Verdict::NONE, instance_double(Builds::Comparison, status_for: nil))).to be_nil
    expect(tag(Verdict::NONE, nil)).to be_nil
  end
end
