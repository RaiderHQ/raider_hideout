require "rails_helper"

RSpec.describe Notifications::Message do
  let(:project) { create(:project, name: "Shop") }
  let(:build) do
    create(:build, project: project, branch: "main", commit_sha: "abcdef1234567", commit_message: "Fix thing\nbody",
                   failed_count: 2, passed_count: 8, skipped_count: 1, duration_ms: 65_000)
  end
  let(:opts) { { host: "example.com" } }

  def message(events = %w[failed])
    described_class.for_build(build, events, url_options: opts)
  end

  it "derives headlines" do
    expect(message(%w[failed recovered]).headline).to eq("build failed")
    expect(message(%w[recovered]).headline).to eq("build recovered")
    expect(message(%w[new_flaky low_pass_rate]).headline).to eq("pass rate 80%")
    expect(message(%w[new_flaky]).headline).to eq("new flaky tests")
    expect(message.title).to eq("Raider: build failed — Shop")
  end

  it "builds summary, commit and urls" do
    m = message
    expect(m.summary).to eq("2 failed, 8 passed, 1 skipped (1m 5s)")
    expect(m.commit).to eq("abcdef1 Fix thing")
    expect(m.branch).to eq("main")
    expect(m.pass_rate).to eq(80)
    expect(m.build_url).to eq("http://example.com/projects/#{project.to_param}/builds/#{build.to_param}")
  end

  it "truncates the commit to 80 characters" do
    build.update!(commit_message: "x" * 200)
    expect(message.commit.length).to eq(80)
  end

  it "uses the pull request helper" do
    build.update!(pr_url: "https://example.com/pr/1")
    expect(message.pr_url).to eq("https://example.com/pr/1")
  end

  it "caps failures at 5 plus a count" do
    run = create(:run, project: project, build: build)
    7.times { |i| create(:test_result, run: run, status: "failed", test_case: create(:test_case, project: project, full_name: "t#{i}")) }
    failures = message.failures
    expect(failures.size).to eq(6)
    expect(failures.first).to eq("t0 (spec/example_spec.rb)")
    expect(failures.last).to eq("and 2 more")
  end

  it "truncates long failure names" do
    run = create(:run, project: project, build: build)
    create(:test_result, run: run, status: "failed", test_case: create(:test_case, project: project, full_name: "n" * 500))
    expect(message.failures.first.length).to eq(200)
  end

  it "lists new flaky tests" do
    fresh = create(:test_case, project: project, full_name: "flaky one")
    create(:test_case_verdict, test_case: fresh, branch: build.branch, flaky: true, flaky_since_build: build)
    known = create(:test_case, project: project, full_name: "known flaky")
    create(:test_case_verdict, test_case: known, branch: build.branch, flaky: true, flaky_since_build: create(:build, project: project))
    other_branch = create(:test_case, project: project, full_name: "other branch")
    create(:test_case_verdict, test_case: other_branch, branch: "feature", flaky: true, flaky_since_build: build)
    expect(message(%w[new_flaky]).new_flaky).to eq([ "flaky one" ])
  end

  it "builds a test message" do
    channel = create(:notification_channel, project: project)
    m = described_class.test(channel, url_options: opts)
    expect(m.headline).to eq("test notification")
    expect(m.branch).to be_nil
    expect([ m.pr_url, m.commit, m.pass_rate ]).to all(be_nil)
    expect(m.failures).to eq([])
    expect(m.build_url).to eq("http://example.com/projects/#{project.to_param}")
  end
end
