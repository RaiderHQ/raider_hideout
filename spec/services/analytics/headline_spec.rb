require "rails_helper"

RSpec.describe Analytics::Headline do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-28 12:00:00") }
  let(:project) { create(:project) }

  around { |example| travel_to(now) { example.run } }

  def headline(query = "") = described_class.new(project, analytics_filter(query, project: project))

  def numbers(headline) = %i[builds pass_rate avg_duration_ms flaky].to_h { |name| [ name, headline.public_send(name).to_h ] }

  it "reports builds, average pass rate, average duration and the newest flaky count, against the previous window" do
    # Current window (30 days): pass rates 90 and 70 (nil skipped), durations 4000 and 6000 (nil skipped).
    analytics_build(project: project, at: 20.days.ago, passed_count: 9, failed_count: 1, duration_ms: 4_000, flaky_count: 5)
    analytics_build(project: project, at: 10.days.ago, passed_count: 7, failed_count: 2, quarantined_count: 1, duration_ms: 6_000, flaky_count: 3)
    analytics_build(project: project, at: 1.day.ago, flaky_count: 2)
    # Previous window (60 to 30 days ago): pass rate 75 (80 and 70), duration 5000, newest flaky 4.
    analytics_build(project: project, at: 50.days.ago, passed_count: 8, failed_count: 2, duration_ms: 5_000, flaky_count: 1)
    analytics_build(project: project, at: 31.days.ago, passed_count: 7, failed_count: 3, duration_ms: 5_000, flaky_count: 4)
    # Outside both windows, and another branch.
    analytics_build(project: project, at: 61.days.ago, passed_count: 0, failed_count: 10)
    analytics_build(project: project, at: 1.day.ago, branch: "feature/x", passed_count: 0, failed_count: 10)

    expect(numbers(headline)).to eq(
      builds: { value: 3, delta: "▲ 50%" },
      pass_rate: { value: 80, delta: "▲ 5 pts" },
      avg_duration_ms: { value: 5_000, delta: "0%" },
      flaky: { value: 2, delta: "▼ 2" }
    )
    expect(headline).not_to be_empty
  end

  it "shows — for every change when the previous window had no builds" do
    analytics_build(project: project, at: 1.day.ago, passed_count: 1, duration_ms: 100, flaky_count: 1)

    expect(numbers(headline).values.map { _1[:delta] }).to eq(%w[— — — —])
  end

  it "shows — for a number missing in either window, and says pt for one point" do
    analytics_build(project: project, at: 40.days.ago, passed_count: 1, failed_count: 1)
    analytics_build(project: project, at: 1.day.ago, passed_count: 51, failed_count: 49, duration_ms: 1_000)

    expect(headline.pass_rate.to_h).to eq(value: 51, delta: "▲ 1 pt")
    expect(headline.avg_duration_ms.to_h).to eq(value: 1_000, delta: "—")
  end

  it "follows branch: and since: and ignores file: and tag:" do
    analytics_build(project: project, at: 5.days.ago, branch: "feature/x")
    analytics_build(project: project, at: 10.days.ago, branch: "feature/x")
    analytics_build(project: project, at: 10.days.ago)

    expect(headline("branch:feature/x").builds.value).to eq(2)
    expect(headline("branch:feature/x since:7d").builds.to_h).to eq(value: 1, delta: "0%")
    expect(headline("file:nothing tag:none").builds.value).to eq(1)
  end

  it "is empty without builds on the branch in the window" do
    analytics_build(project: project, at: 40.days.ago)

    expect(headline).to be_empty
    expect(headline.builds.to_h).to eq(value: 0, delta: "▼ 100%")
    expect(headline.pass_rate.value).to be_nil
    expect(headline.flaky.to_h).to eq(value: nil, delta: "—")
  end
end
