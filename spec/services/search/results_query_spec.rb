require "rails_helper"

RSpec.describe Search::ResultsQuery do
  include ActiveSupport::Testing::TimeHelpers

  let(:project) { create(:project) }
  let(:now) { Time.zone.parse("2026-10-24 12:00:00") }

  around { |example| travel_to(now) { example.run } }

  def tc(name, file: "spec/example_spec.rb")
    create(:test_case, project: project, full_name: name, file_path: file)
  end

  def ids(query = "")
    described_class.new(project, Search::Filter.parse(query), now: now).page(limit: 50, offset: 0).map(&:id)
  end

  it "lists each result on the branch in range, newest first" do
    t = tc("Login")
    old = search_result(t, status: "failed", at: 2.days.ago)
    newer = search_result(t, status: "passed", at: 1.day.ago)
    search_result(t, status: "failed", at: 8.days.ago)
    search_result(t, status: "failed", branch: "feature")
    search_result(create(:test_case, project: create(:project)), status: "failed")

    expect(ids).to eq([ newer.id, old.id ])
    expect(described_class.new(project, Search::Filter.parse(""), now: now).count).to eq(2)
  end

  it "filters each result by status, tags, error, text, name, file and flaky" do
    timeout = search_result(tc("Checkout", file: "spec/cart_spec.rb"), status: "failed", tags: [ "Smoke" ],
                                                                        message: "Net::ReadTimeout", exception: "Net::ReadTimeout")
    passed = search_result(tc("Checkout passes", file: "spec/cart_spec.rb"), status: "passed", tags: [ "smoke" ])
    flaky_case = tc("Flaky one")
    flaky = search_result(flaky_case, status: "passed")
    create(:test_case_verdict, test_case: flaky_case, branch: "main", flaky: true)

    expect(ids("status:failed")).to eq([ timeout.id ])
    expect(ids("tag:smoke")).to contain_exactly(timeout.id, passed.id)
    expect(ids('error:"readtimeout"')).to eq([ timeout.id ])
    expect(ids("readtimeout")).to eq([ timeout.id ])
    expect(ids("name:passes")).to eq([ passed.id ])
    expect(ids("file:cart")).to contain_exactly(timeout.id, passed.id)
    expect(ids("is:flaky")).to eq([ flaky.id ])
  end

  it "sorts by recent, duration and name, and treats failures as recent" do
    a = search_result(tc("A"), status: "passed", duration: 50, at: 3.days.ago)
    b = search_result(tc("B"), status: "passed", duration: 500, at: 2.days.ago)
    c = search_result(tc("C"), status: "passed", duration: 5, at: 1.day.ago)
    expect(ids).to eq([ c.id, b.id, a.id ])
    expect(ids("sort:failures")).to eq([ c.id, b.id, a.id ])
    expect(ids("sort:duration")).to eq([ b.id, a.id, c.id ])
    expect(ids("sort:name")).to eq([ a.id, b.id, c.id ])
  end

  it "preloads what a row shows" do
    search_result(tc("A"), status: "failed")
    row = described_class.new(project, Search::Filter.parse(""), now: now).page(limit: 50, offset: 0).first
    expect(row.association(:run)).to be_loaded
    expect(row.run.association(:build)).to be_loaded
    expect(row.association(:test_case)).to be_loaded
  end

  it "shows the first line of a failure message, truncated" do
    expect(described_class.first_line("  expected true\n  got false")).to eq("expected true")
    expect(described_class.first_line("x" * 200).length).to eq(160)
    expect(described_class.first_line(nil)).to eq("")
  end

  it "matches a capitalised non-ASCII name when typed exactly, by field and bare" do
    hit = search_result(tc("Überweisung prüfen"), status: "passed")
    search_result(tc("Cart totals"), status: "passed")

    expect(ids("name:Überweisung")).to eq([ hit.id ])
    expect(ids("Überweisung")).to eq([ hit.id ])
    expect(ids("name:cArT")).not_to include(hit.id)
  end

  it "filters each result by status quarantined and by an active quarantine" do
    held_case = tc("Held")
    held = search_result(held_case, status: "quarantined")
    passed_later = search_result(held_case, status: "passed")
    Quarantine.quarantine!(test_case: held_case, user: create(:user), reason: "flaky", days: 14)
    search_result(tc("Other"), status: "failed")

    expect(ids("status:quarantined")).to eq([ held.id ])
    expect(ids("is:quarantined")).to eq([ passed_later.id, held.id ])
  end
end
