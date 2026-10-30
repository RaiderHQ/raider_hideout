require "rails_helper"

RSpec.describe Notifications::Rules do
  let(:project) { create(:project) }
  let(:channel) { create(:notification_channel, project: project, on_new_flaky: true) }

  def make_build(status:, branch: "main", at: Time.current, **attrs)
    create(:build, project: project, branch: branch, status: status, created_at: at, **attrs)
  end

  it "fires failed" do
    expect(described_class.call(channel, make_build(status: "failed"))).to eq(%w[failed])
  end

  it "does not fire disabled rules" do
    channel.update!(on_failed: false)
    expect(described_class.call(channel, make_build(status: "failed"))).to eq([])
  end

  describe "recovered" do
    it "fires when the previous complete build on the branch failed" do
      make_build(status: "failed", at: 2.hours.ago)
      expect(described_class.call(channel, make_build(status: "passed"))).to eq(%w[recovered])
    end

    it "skips an incomplete previous build and looks at the one before" do
      make_build(status: "failed", at: 2.hours.ago)
      incomplete = make_build(status: "incomplete", at: 1.hour.ago, expected_shards: 2)
      create(:run, project: project, build: incomplete)
      expect(described_class.call(channel, make_build(status: "passed"))).to eq(%w[recovered])
    end

    it "orders builds with identical created_at by id" do
      t = Time.current.change(usec: 0)
      make_build(status: "failed", at: t)
      current = make_build(status: "passed", at: t)
      make_build(status: "failed", at: t) # later id, same time: not previous
      expect(described_class.call(channel, current)).to eq(%w[recovered])
      earlier_pass = make_build(status: "passed", at: t - 1.minute)
      expect(described_class.call(channel, earlier_pass)).to eq([])
    end

    it "does not fire when the incomplete previous build hides an older pass" do
      make_build(status: "passed", at: 3.hours.ago)
      incomplete = make_build(status: "failed", at: 1.hour.ago, expected_shards: 2)
      create(:run, project: project, build: incomplete)
      expect(described_class.call(channel, make_build(status: "passed"))).to eq([])
    end

    it "ignores failures on other branches" do
      make_build(status: "failed", branch: "other", at: 2.hours.ago)
      expect(described_class.call(channel, make_build(status: "passed"))).to eq([])
    end

    it "does not fire for the first-ever build" do
      expect(described_class.call(channel, make_build(status: "passed"))).to eq([])
    end
  end

  describe "new_flaky" do
    it "fires when a test turned flaky in this build" do
      build = make_build(status: "passed")
      create(:test_case_verdict, test_case: create(:test_case, project: project), branch: build.branch, flaky: true,
                                 flaky_since_build: build)
      expect(described_class.call(channel, build)).to eq(%w[new_flaky])
    end

    it "only looks at the build's branch" do
      build = make_build(status: "passed")
      create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "other", flaky: true,
                                 flaky_since_build: build)
      expect(described_class.call(channel, build)).to eq([])
    end

    it "does not fire for an older flaky test" do
      older = make_build(status: "passed", at: 1.day.ago)
      build = make_build(status: "passed")
      create(:test_case_verdict, test_case: create(:test_case, project: project), branch: build.branch, flaky: true,
                                 flaky_since_build: older)
      expect(described_class.call(channel, build)).to eq([])
    end
  end

  describe "low_pass_rate" do
    before { channel.update!(pass_rate_below: 90) }

    it "fires under the threshold" do
      build = make_build(status: "passed", passed_count: 8, failed_count: 2)
      expect(described_class.call(channel, build)).to eq(%w[low_pass_rate])
    end

    it "does not fire when nothing executed" do
      expect(described_class.call(channel, make_build(status: "passed"))).to eq([])
    end
  end

  it "returns events in the fixed order" do
    channel.update!(pass_rate_below: 90)
    build = make_build(status: "failed", passed_count: 8, failed_count: 2)
    create(:test_case_verdict, test_case: create(:test_case, project: project), branch: build.branch, flaky: true,
                               flaky_since_build: build)
    expect(described_class.call(channel, build)).to eq(%w[failed new_flaky low_pass_rate])
  end
end
