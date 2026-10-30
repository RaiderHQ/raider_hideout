require "rails_helper"

RSpec.describe Analytics::FlakyRanking do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-28 12:00:00") }
  let(:project) { create(:project) }

  around { |example| travel_to(now) { example.run } }

  def tc(name, file: "spec/example_spec.rb") = create(:test_case, project: project, full_name: name, file_path: file)

  def flaky(test, rate, branch: "main", **attributes)
    create(:test_case_verdict, test_case: test, branch: branch, flaky: true, flip_rate: rate, **attributes)
  end

  def rows(query = "", limit: 10) = described_class.new(project, analytics_filter(query, project: project)).rows(limit: limit)

  it "lists flaky verdicts on the branch with flip rate, reason, first flaky build, samples and quarantine" do
    test = tc("Login works")
    build = create(:build, project: project)
    flaky(test, 0.456, flaky_reason: "flips", flaky_since_build: build, sample_count: 12)
    create(:quarantine, test_case: test)

    expect(rows.sole.to_h).to eq(test_case: test, flip_rate: 46, reason: "flips", flaky_since_build: build, sample_count: 12,
                                 quarantined: true)
  end

  it "orders by flip rate with null as 0 (kept nil), then name and id, and ignores other branches, projects and non-flaky verdicts" do
    high = tc("Zulu")
    none = tc("Alpha")
    low = tc("Bravo")
    twin = tc("Bravo", file: "spec/other_spec.rb")
    flaky(high, 0.9)
    flaky(none, nil)
    flaky(low, 0.1)
    flaky(twin, 0.1)
    flaky(tc("Elsewhere"), 0.5, branch: "feature/x")
    create(:test_case_verdict, test_case: tc("Steady"), branch: "main", flaky: false, flip_rate: 0.8)
    flaky(create(:test_case, project: create(:project)), 0.7)

    expect(rows.map(&:test_case)).to eq([ high, low, twin, none ])
    expect(rows.last.flip_rate).to be_nil
    expect(rows("branch:feature/x").map { _1.test_case.full_name }).to eq([ "Elsewhere" ])
    expect(rows(limit: 1).size).to eq(1)
  end

  it "narrows by file: without needing a result" do
    login = tc("Login works", file: "spec/login_spec.rb")
    flaky(login, 0.2)
    flaky(tc("Cart totals", file: "spec/cart_spec.rb"), 0.3)

    expect(rows("file:login").map(&:test_case)).to eq([ login ])
  end

  it "with tag:, keeps only tests with a result in the window carrying the tag" do
    tagged = tc("Tagged")
    old = tc("Tagged long ago")
    untagged = tc("Untagged")
    [ tagged, old, untagged ].each { |test| flaky(test, 0.5) }
    search_result(tagged, status: "passed", tags: [ "smoke" ], at: 2.days.ago)
    search_result(old, status: "passed", tags: [ "smoke" ], at: 40.days.ago)
    search_result(untagged, status: "passed", at: 2.days.ago)

    expect(rows("tag:smoke").map(&:test_case)).to eq([ tagged ])
    expect(rows.size).to eq(3)
  end

  it "marks a test as not quarantined when the quarantine was released" do
    test = tc("Login works")
    flaky(test, 0.2)
    quarantine = create(:quarantine, test_case: test)
    quarantine.update!(released_at: 1.day.ago)

    expect(rows.sole.quarantined).to eq(false)
  end
end
