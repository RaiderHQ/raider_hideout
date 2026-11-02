require "rails_helper"

RSpec.describe Push::Recipients do
  let(:project) { create(:project) }
  let(:build) { create(:build, project: project, branch: "main", status: "failed", default_branch: "main") }

  it "returns every device of a member for a default-branch failure" do
    user, first = subscribe_member(project)
    second = create_subscription(user, fcm_endpoint("second"))
    expect(described_class.call(build)).to eq([ [ first, %w[failed] ], [ second, %w[failed] ] ])
  end

  it "skips feature-branch failures and passed builds" do
    subscribe_member(project)
    expect(described_class.call(create(:build, project: project, branch: "feature/x", status: "failed", default_branch: "main"))).to eq([])
    expect(described_class.call(create(:build, project: project, branch: "main", status: "passed", default_branch: "main"))).to eq([])
  end

  it "skips a project the user muted" do
    user, = subscribe_member(project)
    PushMutedProject.create!(user: user, project: project)
    expect(described_class.call(build)).to eq([])
  end

  it "skips a user removed from the organization who kept a subscription" do
    user, = subscribe_member(project)
    Membership.where(user: user, organization: project.organization).destroy_all
    expect(described_class.call(build)).to eq([])
  end

  it "skips members of other organizations" do
    subscribe_member(create(:project))
    expect(described_class.call(build)).to eq([])
  end

  it "skips users who switched default-branch failures off" do
    user, = subscribe_member(project)
    user.push_preference!.update!(default_branch_failures: false)
    expect(described_class.call(build)).to eq([])
  end

  describe "new_flaky (off by default)" do
    let(:passed) { create(:build, project: project, branch: "main", status: "passed", default_branch: "main") }

    before do
      create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "main", flaky: true, flaky_since_build: passed)
    end

    it "is not sent by default and is sent once opted in" do
      user, subscription = subscribe_member(project)
      expect(described_class.call(passed)).to eq([])
      user.push_preference!.update!(new_flaky: true)
      expect(described_class.call(passed)).to eq([ [ subscription, %w[new_flaky] ] ])
    end
  end

  describe "gate_failed (off by default)" do
    it "follows gate_status == failed once opted in" do
      user, subscription = subscribe_member(project)
      passed = create(:build, project: project, branch: "feature/x", status: "passed", default_branch: "main")
      passed.update_columns(gate_status: "failed")
      expect(described_class.call(passed)).to eq([])
      user.push_preference!.update!(gate_failures: true)
      expect(described_class.call(passed)).to eq([ [ subscription, %w[gate_failed] ] ])
    end
  end

  describe "rerun_result" do
    let(:failed_build) { create(:build, project: project, branch: "main", status: "failed", default_branch: "main", ci_run_key: "gha:1") }
    let(:passed_build) { create(:build, project: project, branch: "main", status: "passed", default_branch: "main", ci_run_key: "gha:2") }

    def rerun!(build, user, status: "accepted", attempt_before: 1)
      BuildRerun.create!(build: build, user: user, status: status, attempt_before: attempt_before)
    end

    it "goes to the starter only, for a passed re-run" do
      starter, starter_sub = subscribe_member(project)
      subscribe_member(project)
      rerun!(passed_build, starter)
      expect(described_class.call(passed_build, attempt: 2)).to eq([ [ starter_sub, %w[rerun_result] ] ])
    end

    it "adds to a default-branch failure for the starter while others get failed" do
      starter, starter_sub = subscribe_member(project)
      _, other_sub = subscribe_member(project)
      rerun!(failed_build, starter)
      expect(described_class.call(failed_build, attempt: 2)).to eq([ [ starter_sub, %w[rerun_result failed] ], [ other_sub, %w[failed] ] ])
    end

    it "goes to the starter only for the attempt their re-run produced" do
      starter, starter_sub = subscribe_member(project)
      rerun!(passed_build, starter)
      expect(described_class.call(passed_build, attempt: 2)).to eq([ [ starter_sub, %w[rerun_result] ] ])
      expect(described_class.call(passed_build, attempt: 3)).to eq([])
    end

    it "respects the rerun_results switch" do
      starter, starter_sub = subscribe_member(project)
      starter.push_preference!.update!(rerun_results: false)
      rerun!(failed_build, starter)
      expect(described_class.call(failed_build, attempt: 2)).to eq([ [ starter_sub, %w[failed] ] ])
    end

    it "skips a starter removed from the organization or who muted the project" do
      removed, = subscribe_member(project)
      rerun!(passed_build, removed)
      Membership.where(user: removed, organization: project.organization).destroy_all
      expect(described_class.call(passed_build, attempt: 2)).to eq([])

      muted, = subscribe_member(project)
      rerun!(passed_build, muted)
      PushMutedProject.create!(user: muted, project: project)
      expect(described_class.call(passed_build, attempt: 2)).to eq([])
    end

    it "needs an accepted re-run started before this attempt" do
      starter, = subscribe_member(project)
      rerun!(passed_build, starter, status: "rejected")
      expect(described_class.call(passed_build, attempt: 2)).to eq([])
      rerun!(passed_build, starter, attempt_before: 2)
      expect(described_class.call(passed_build, attempt: 2)).to eq([])
    end

    it "is not sent for attempt 1" do
      starter, = subscribe_member(project)
      rerun!(passed_build, starter)
      expect(described_class.call(passed_build)).to eq([])
    end
  end
end
