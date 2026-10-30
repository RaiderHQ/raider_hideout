require "rails_helper"

RSpec.describe Search::TestsQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:project) { create(:project) }
  let(:now) { Time.zone.parse("2026-10-24 12:00:00") }

  def tc(name, file: "spec/example_spec.rb", line: 3)
    create(:test_case, project: project, full_name: name, file_path: file, line_number: line)
  end

  def names(query = "", **opts)
    q = described_class.new(project, Search::Filter.parse(query), now: now, **opts)
    q.page(limit: 50, offset: 0).map { _1.test_case.full_name }
  end

  around { |example| travel_to(now) { example.run } }

  it "lists tests with a result on the branch in range, with stats" do
    login = tc("Login works", line: 7)
    search_result(login, status: "failed", at: 3.days.ago, duration: 100)
    search_result(login, status: "skipped", at: 2.days.ago, duration: 50)
    search_result(login, status: "passed", at: 1.day.ago, duration: 300)
    search_result(tc("Old"), status: "failed", at: 8.days.ago)
    search_result(tc("Other branch"), status: "failed", branch: "feature")

    q = described_class.new(project, Search::Filter.parse(""), now: now)
    rows = q.page(limit: 50, offset: 0)

    expect(q.count).to eq(1)
    expect(rows.size).to eq(1)
    expect(rows.first).to have_attributes(test_case: login, latest_status: "passed", pass_rate: 50, failures: 1,
                                          avg_duration_ms: 150, flaky: false)
    expect(rows.first.last_run_at).to be_within(1.second).of(1.day.ago)
  end

  it "leaves pass rate blank when only skipped or pending results ran" do
    search_result(tc("Skipped"), status: "skipped")
    expect(described_class.new(project, Search::Filter.parse(""), now: now).page(limit: 50, offset: 0).first.pass_rate).to be_nil
  end

  it "uses the range edges" do
    search_result(tc("Inside"), status: "passed", at: 7.days.ago + 1.minute)
    search_result(tc("Outside"), status: "passed", at: 7.days.ago - 1.minute)
    search_result(tc("Day old"), status: "passed", at: 23.hours.ago)
    expect(names).to contain_exactly("Inside", "Day old")
    expect(names("since:24h")).to eq([ "Day old" ])
  end

  it "uses the project's default branch unless one is given" do
    create(:build, project: project, default_branch: "trunk")
    search_result(tc("Trunk test"), status: "passed", branch: "trunk")
    search_result(tc("Main test"), status: "passed", branch: "main")
    expect(names).to eq([ "Trunk test" ])
    expect(names("branch:main")).to eq([ "Main test" ])
  end

  it "filters by text, name and file, case-insensitively" do
    search_result(tc("User signs in", file: "spec/auth/login_spec.rb"), status: "passed")
    search_result(tc("Cart totals", file: "spec/cart_spec.rb"), status: "passed")
    expect(names("LOGIN")).to eq([ "User signs in" ])
    expect(names('"signs in"')).to eq([ "User signs in" ])
    expect(names("name:cart")).to eq([ "Cart totals" ])
    expect(names("file:spec/cart")).to eq([ "Cart totals" ])
    expect(names("cart signs")).to eq([])
  end

  it "matches % and _ literally" do
    search_result(tc("Loads 100% of items"), status: "passed")
    search_result(tc("Loads 1000 items"), status: "passed")
    search_result(tc("snake_case name"), status: "passed")
    search_result(tc("snakeXcase name"), status: "passed")
    expect(names("name:100%")).to eq([ "Loads 100% of items" ])
    expect(names("name:snake_case")).to eq([ "snake_case name" ])
  end

  it "matches status on the latest result in range only" do
    flaky_now_skipped = tc("Was failing, now skipped")
    search_result(flaky_now_skipped, status: "failed", at: 2.days.ago)
    search_result(flaky_now_skipped, status: "skipped", at: 1.day.ago)
    search_result(tc("Failing"), status: "failed")
    expect(names("status:failed")).to eq([ "Failing" ])
    expect(names("status:skipped,failed")).to contain_exactly("Failing", "Was failing, now skipped")
  end

  it "matches tags on the latest result, all tags required" do
    retagged = tc("Retagged")
    search_result(retagged, status: "passed", tags: [ "Smoke" ], at: 2.days.ago)
    search_result(retagged, status: "passed", tags: [ "regression" ], at: 1.day.ago)
    search_result(tc("Slow smoke"), status: "passed", tags: [ "Smoke", "slow test" ])
    search_result(tc("Piped"), status: "passed", tags: [ "a|b" ])
    expect(names("tag:smoke")).to eq([ "Slow smoke" ])
    expect(names('tag:smoke tag:"slow test"')).to eq([ "Slow smoke" ])
    expect(names("tag:regression")).to eq([ "Retagged" ])
    expect(names("tag:ab")).to eq([ "Piped" ])
    expect(names("tag:smo")).to eq([])
  end

  it "matches error text on any failed result in range" do
    timeout = tc("Times out")
    search_result(timeout, status: "failed", message: "Net::ReadTimeout after 30s", exception: "Net::ReadTimeout", at: 2.days.ago)
    search_result(timeout, status: "passed", at: 1.day.ago)
    search_result(tc("Assertion"), status: "failed", message: "expected 1, got 2", exception: "RSpec::Expectations::ExpectationNotMetError")
    search_result(tc("Passed with message"), status: "passed", message: "timeout")
    expect(names('error:"readtimeout"')).to eq([ "Times out" ])
    expect(names("error:ExpectationNotMet")).to eq([ "Assertion" ])
  end

  it "filters flaky tests by the branch verdict" do
    flaky = tc("Flaky")
    search_result(flaky, status: "passed")
    create(:test_case_verdict, test_case: flaky, branch: "main", flaky: true)
    other = tc("Flaky elsewhere")
    search_result(other, status: "passed")
    create(:test_case_verdict, test_case: other, branch: "feature", flaky: true)
    expect(names("is:flaky")).to eq([ "Flaky" ])
    expect(described_class.new(project, Search::Filter.parse(""), now: now).page(limit: 50, offset: 0)
                          .to_h { [ _1.test_case.full_name, _1.flaky ] }).to eq("Flaky" => true, "Flaky elsewhere" => false)
  end

  it "never shows another project's tests" do
    search_result(create(:test_case, project: create(:project), full_name: "Foreign"), status: "failed")
    expect(names).to eq([])
  end

  it "sorts by failures, recent, duration and name" do
    a = tc("A slow")
    search_result(a, status: "passed", duration: 900, at: 3.days.ago)
    b = tc("B failing")
    2.times { search_result(b, status: "failed", duration: 10, at: 2.days.ago) }
    c = tc("C recent")
    search_result(c, status: "failed", duration: 20, at: 1.hour.ago)
    expect(names).to eq([ "B failing", "C recent", "A slow" ])
    expect(names("sort:recent")).to eq([ "C recent", "B failing", "A slow" ])
    expect(names("sort:duration")).to eq([ "A slow", "C recent", "B failing" ])
    expect(names("sort:name")).to eq([ "A slow", "B failing", "C recent" ])
  end

  it "counts quarantined results as failures for the failure count, pass rate and sort:failures" do
    held = tc("A held")
    search_result(held, status: "passed", at: 2.days.ago)
    search_result(held, status: "quarantined", at: 1.day.ago)
    always = tc("B always held")
    2.times { search_result(always, status: "quarantined") }
    search_result(tc("C passing"), status: "passed")

    rows = described_class.new(project, Search::Filter.parse(""), now: now).page(limit: 50, offset: 0).index_by { _1.test_case.full_name }

    expect(rows["A held"]).to have_attributes(failures: 1, pass_rate: 50)
    expect(rows["B always held"]).to have_attributes(failures: 2, pass_rate: 0)
    expect(names).to eq([ "B always held", "A held", "C passing" ])
  end

  it "paginates" do
    3.times { |i| search_result(tc("T#{i}"), status: "passed") }
    q = described_class.new(project, Search::Filter.parse("sort:name"), now: now)
    expect(q.count).to eq(3)
    expect(q.page(limit: 2, offset: 2).map { _1.test_case.full_name }).to eq([ "T2" ])
  end

  it "matches a capitalised non-ASCII name when typed exactly, by field and bare" do
    search_result(tc("Überweisung prüfen"), status: "passed")
    search_result(tc("Cart totals"), status: "passed")

    expect(names("name:Überweisung")).to eq([ "Überweisung prüfen" ])
    expect(names("Überweisung")).to eq([ "Überweisung prüfen" ])
    expect(names("name:cArT")).to eq([ "Cart totals" ])
  end

  it "filters by latest status quarantined and by an active quarantine" do
    user = create(:user)
    held = tc("Held")
    search_result(held, status: "quarantined")
    Quarantine.quarantine!(test_case: held, user: user, reason: "flaky", days: 14)
    released = tc("Released")
    search_result(released, status: "quarantined", at: 2.days.ago)
    search_result(released, status: "passed")
    Quarantine.quarantine!(test_case: released, user: user, reason: "flaky", days: 14).release!(user: user)
    search_result(tc("Plain"), status: "failed")

    expect(names("status:quarantined")).to eq([ "Held" ])
    expect(names("is:quarantined")).to eq([ "Held" ])
    expect(described_class.new(project, Search::Filter.parse(""), now: now).page(limit: 50, offset: 0)
                          .to_h { [ _1.test_case.full_name, _1.latest_status ] })
      .to include("Held" => "quarantined", "Released" => "passed")
  end

  it "matches error: on a quarantined result as well as a failed one" do
    search_result(tc("Held"), status: "quarantined").update!(failure_message: "Net::ReadTimeout")
    expect(names("error:readtimeout")).to eq([ "Held" ])
  end
end
