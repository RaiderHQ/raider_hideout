require "rails_helper"

RSpec.describe Analytics::TestRanking do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-28 12:00:00") }
  let(:project) { create(:project) }

  around { |example| travel_to(now) { example.run } }

  def tc(name, file: "spec/example_spec.rb") = create(:test_case, project: project, full_name: name, file_path: file)

  def rows(mode, query = "", limit: 10)
    described_class.new(project, analytics_filter(query, project: project), mode: mode).rows(limit: limit)
  end

  describe "failing" do
    it "counts failures over executed results, floors the rate and keeps the last failure time" do
      login = tc("Login works", file: "spec/login_spec.rb")
      search_result(login, status: "failed", at: 3.days.ago)
      search_result(login, status: "passed", at: 2.days.ago)
      search_result(login, status: "quarantined", at: 1.day.ago)
      search_result(login, status: "skipped", at: 12.hours.ago)
      search_result(login, status: "pending", at: 6.hours.ago)

      row = rows("failing").sole

      expect(row.to_h.except(:test_case)).to eq(
        failures: 2, executed: 3, failure_rate: 66, last_failure_at: 1.day.ago, avg_duration_ms: 100,
        max_duration_ms: 100, total_duration_ms: 300, flaky: false, quarantined: false
      )
      expect(row.test_case).to eq(login)
    end

    it "leaves out tests without a failure, and orders by failures, rate, name and id" do
      a = tc("Alpha")
      b = tc("Bravo")
      c = tc("Charlie")
      twin = tc("Alpha", file: "spec/other_spec.rb")
      passing = tc("Passing")
      [ c, b, a, twin ].each { |test| 2.times { search_result(test, status: "failed") } }
      search_result(c, status: "failed")  # c: 3 of 3
      search_result(b, status: "passed")  # b: 2 of 3
      search_result(passing, status: "passed")

      expect(rows("failing").map(&:test_case)).to eq([ c, a, twin, b ])
    end

    it "marks flaky tests on the branch and actively quarantined tests" do
      test = tc("Login works")
      search_result(test, status: "failed")
      create(:test_case_verdict, test_case: test, branch: "main", flaky: true)
      create(:quarantine, test_case: test)

      expect(rows("failing").sole.to_h.slice(:flaky, :quarantined)).to eq(flaky: true, quarantined: true)
    end

    it "limits the rows" do
      3.times { |i| search_result(tc("Test #{i}"), status: "failed") }
      expect(rows("failing", limit: 2).size).to eq(2)
    end
  end

  describe "slowest" do
    it "averages, maxes and sums executed durations, ordered by average, name and id" do
      fast = tc("Fast")
      slow = tc("Slow")
      twin = tc("Slow", file: "spec/other_spec.rb")
      search_result(fast, status: "passed", duration: 10)
      search_result(fast, status: "failed", duration: 30)
      search_result(fast, status: "skipped", duration: 9_000)
      search_result(slow, status: "passed", duration: 500)
      search_result(twin, status: "quarantined", duration: 500)
      search_result(tc("Never ran"), status: "pending", duration: 7_000)

      result = rows("slowest")

      expect(result.map(&:test_case)).to eq([ slow, twin, fast ])
      expect(result.last.to_h.slice(:avg_duration_ms, :max_duration_ms, :executed, :total_duration_ms))
        .to eq(avg_duration_ms: 20, max_duration_ms: 30, executed: 2, total_duration_ms: 40)
    end
  end

  describe "scoping" do
    let(:test) { tc("Login works", file: "spec/login_spec.rb") }

    before do
      search_result(test, status: "failed", at: 30.days.ago, tags: [ "smoke" ])  # the window edge counts
      search_result(test, status: "failed", at: 31.days.ago, tags: [ "smoke" ])
      search_result(test, status: "failed", at: 1.day.ago, branch: "feature/x")
      search_result(test, status: "failed", at: 1.day.ago, tags: [ "login" ])
    end

    it "counts the default branch over 30 days, the edge included" do
      expect(rows("failing").sole.failures).to eq(2)
    end

    it "follows branch:, since:, tag: and file:" do
      expect(rows("failing", "branch:feature/x").sole.failures).to eq(1)
      expect(rows("failing", "since:90d").sole.failures).to eq(3)
      expect(rows("failing", "since:7d").sole.failures).to eq(1)
      expect(rows("failing", "tag:smoke").sole.failures).to eq(1)
      expect(rows("failing", "tag:smoke tag:login")).to eq([])
      expect(rows("failing", "file:login_spec").sole.failures).to eq(2)
      expect(rows("failing", "file:checkout")).to eq([])
    end

    it "matches a file with LIKE wildcards literally (Review Focus 1)" do
      expect(rows("failing", "file:login%")).to eq([])
      expect(rows("failing", "file:login_spec")).not_to be_empty
      expect(rows("failing", "file:login_spe_")).to eq([])
    end
  end

  it "refuses an unknown mode" do
    expect { described_class.new(project, analytics_filter(project: project), mode: "bogus") }.to raise_error(ArgumentError)
  end
end
