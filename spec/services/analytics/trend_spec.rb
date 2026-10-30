require "rails_helper"

RSpec.describe Analytics::Trend do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-28 12:00:00") }
  let(:project) { create(:project) }
  let(:login) { create(:test_case, project: project, full_name: "Login works", file_path: "spec/login_spec.rb") }

  around { |example| travel_to(now) { example.run } }

  def trend(query = "") = described_class.new(project, analytics_filter(query, project: project))

  def point(trend, date) = trend.points.find { |p| p.date == Date.parse(date) }

  it "has one bucket per day over the whole 7-day window, with nil gaps" do
    build = analytics_build(project: project, at: Time.zone.parse("2026-10-27 09:00"), duration_ms: 3_000, flaky_count: 2)
    analytics_result(build: build, test_case: login, status: "failed", duration: 100)
    analytics_result(build: build, test_case: login, status: "passed", duration: 300)
    analytics_result(build: build, test_case: login, status: "passed", duration: 200)
    analytics_result(build: build, test_case: login, status: "skipped", duration: 9_000)

    weekly = trend("since:7d")

    expect(weekly).not_to be_weekly
    expect(weekly.points.map(&:date)).to eq((Date.new(2026, 10, 21)..Date.new(2026, 10, 28)).to_a)
    expect(point(weekly, "2026-10-27").to_h).to eq(
      date: Date.new(2026, 10, 27), executed: 3, failed: 1, failure_rate: 33, avg_test_duration_ms: 200,
      avg_build_duration_ms: 3_000, flaky_count: 2
    )
    expect(point(weekly, "2026-10-26").to_h).to eq(
      date: Date.new(2026, 10, 26), executed: 0, failed: 0, failure_rate: nil, avg_test_duration_ms: nil,
      avg_build_duration_ms: nil, flaky_count: nil
    )
  end

  it "covers 31 days for 30d and counts the window edge in the first bucket" do
    edge = analytics_build(project: project, at: now - 30.days)
    analytics_result(build: edge, test_case: login, status: "failed")
    before = analytics_build(project: project, at: now - 30.days - 1.second)
    analytics_result(build: before, test_case: login, status: "failed")

    points = trend.points

    expect(points.size).to eq(31)
    expect(points.first.to_h.slice(:date, :executed, :failed)).to eq(date: Date.new(2026, 9, 28), executed: 1, failed: 1)
  end

  it "has ISO week buckets starting on Monday for 90d" do
    monday = analytics_build(project: project, at: Time.zone.parse("2026-10-19 00:30"), flaky_count: 1, duration_ms: 1_000)
    sunday = analytics_build(project: project, at: Time.zone.parse("2026-10-25 23:30"), flaky_count: 4, duration_ms: 3_000)
    analytics_result(build: monday, test_case: login, status: "passed")
    analytics_result(build: sunday, test_case: login, status: "quarantined")

    weekly = trend("since:90d")

    expect(weekly).to be_weekly
    expect(weekly.points.map(&:date).first(2)).to eq([ Date.new(2026, 7, 27), Date.new(2026, 8, 3) ])
    expect(weekly.points.last.date).to eq(Date.new(2026, 10, 26))
    expect(weekly.points.size).to eq(14)
    expect(point(weekly, "2026-10-19").to_h).to eq(
      date: Date.new(2026, 10, 19), executed: 2, failed: 1, failure_rate: 50, avg_test_duration_ms: 100,
      avg_build_duration_ms: 2_000, flaky_count: 4
    )
  end

  it "buckets weeks in Time.zone: Monday 00:30 and Sunday 23:30 local share an ISO week in Europe/Copenhagen" do
    Time.use_zone("Europe/Copenhagen") do
      monday = analytics_build(project: project, at: Time.zone.parse("2026-10-19 00:30"))
      sunday = analytics_build(project: project, at: Time.zone.parse("2026-10-25 23:30"))
      analytics_result(build: monday, test_case: login, status: "failed")
      analytics_result(build: sunday, test_case: login, status: "passed")

      weekly = trend("since:90d")

      expect(weekly.points.size).to eq(14)
      expect(point(weekly, "2026-10-19").to_h.slice(:executed, :failed)).to eq(executed: 2, failed: 1)
      expect(point(weekly, "2026-10-26").executed).to eq(0)
    end
  end

  it "narrows the result series by tag: and file: but not the build series" do
    build = analytics_build(project: project, at: 1.day.ago, duration_ms: 5_000, flaky_count: 3)
    analytics_result(build: build, test_case: login, status: "failed", tags: [ "smoke" ])
    analytics_result(build: build, test_case: login, status: "passed")

    tagged = point(trend("tag:smoke"), 1.day.ago.to_date.iso8601)
    other = point(trend("file:checkout"), 1.day.ago.to_date.iso8601)

    expect(tagged.to_h.slice(:executed, :failure_rate, :avg_build_duration_ms, :flaky_count))
      .to eq(executed: 1, failure_rate: 100, avg_build_duration_ms: 5_000, flaky_count: 3)
    expect(other.to_h.slice(:executed, :failure_rate, :flaky_count)).to eq(executed: 0, failure_rate: nil, flaky_count: 3)
  end

  it "follows branch:" do
    build = analytics_build(project: project, at: 1.day.ago, branch: "feature/x", flaky_count: 7)
    analytics_result(build: build, test_case: login, status: "failed")

    expect(trend.points.sum(&:executed)).to eq(0)
    expect(trend("branch:feature/x").points.sum(&:executed)).to eq(1)
    expect(trend("branch:feature/x").points.filter_map(&:flaky_count)).to eq([ 7 ])
  end
end
