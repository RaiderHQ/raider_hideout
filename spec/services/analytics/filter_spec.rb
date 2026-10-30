require "rails_helper"

RSpec.describe Analytics::Filter do
  def parse(query) = described_class.parse(query, default_branch: "main")

  it "defaults to the project's default branch over the last 30 days with no notices" do
    filter = parse("")

    expect(filter.branch).to eq("main")
    expect(filter.since).to eq("30d")
    expect(filter.days).to eq(30)
    expect(filter.length).to eq(30.days)
    expect([ filter.file, filter.tags, filter.notices ]).to eq([ nil, [], [] ])
    expect(filter.to_query).to eq("")
    expect(filter).not_to be_narrowed
  end

  it "accepts branch:, repeated tag:, file: and since:" do
    filter = parse(%(branch:feature/x tag:Smoke tag:login file:"spec/a b_spec.rb" since:7d))

    expect(filter.branch).to eq("feature/x")
    expect(filter.tags).to eq(%w[smoke login])
    expect(filter.file).to eq("spec/a b_spec.rb")
    expect(filter.since).to eq("7d")
    expect(filter.notices).to eq([])
    expect(filter).to be_narrowed
    expect(filter.to_query).to eq(%(file:"spec/a b_spec.rb" branch:feature/x tag:smoke tag:login since:7d))
  end

  it "accepts since:90d and prints the default range nowhere" do
    expect(parse("since:90d").to_query).to eq("since:90d")
    expect(parse("since:90d").range_start(Time.zone.parse("2026-10-28 12:00"))).to eq(Time.zone.parse("2026-07-30 12:00"))
    expect(parse("since:30d").to_query).to eq("")
  end

  it "falls back to 30d on since:24h or any other range, with a notice" do
    filter = parse("since:24h")
    expect(filter.since).to eq("30d")
    expect(filter.notices).to eq([ %(Ignored "since:24h": use 7d, 30d or 90d) ])

    expect(parse("since:1y").notices).to eq([ %(Ignored "since:1y": use 7d, 30d or 90d) ])
    expect(parse("since:24h since:7d").since).to eq("7d")
  end

  it "ignores every other term with a notice and keeps the accepted ones" do
    filter = parse(%(login "two words" name:foo status:failed is:flaky sort:duration error:"Timeout" foo:bar tag:smoke))

    expect(filter.notices).to eq([
      %(Ignored "login": not an analytics filter),
      %(Ignored "two words": not an analytics filter),
      %(Ignored "name:foo": not an analytics filter),
      %(Ignored "status:failed": not an analytics filter),
      %(Ignored "is:flaky": not an analytics filter),
      %(Ignored "sort:duration": not an analytics filter),
      %(Ignored "error:"Timeout"": not an analytics filter),
      %(Ignored "foo:bar": not an analytics filter)
    ])
    expect(filter.tags).to eq(%w[smoke])
    expect(filter.to_query).to eq("tag:smoke")
  end

  it "keeps Explore's notices for empty values and long queries" do
    expect(parse("branch:").notices).to eq([ %(Ignored "branch:": empty value) ])
    expect(parse("x" * 600).notices).to include("Only the first 500 characters are used")
    expect(parse(Array.new(12) { |i| "tag:t#{i}" }.join(" ")).notices).to eq([ "Only the first 10 terms are used" ])
  end

  it "replaces the file term for the spec file links, and a path with spaces or wildcards reads back unchanged (Review Focus 1)" do
    filter = parse("file:spec/a_spec.rb tag:smoke")
    expect(filter.to_query(file: "spec/b c_spec.rb")).to eq(%(file:"spec/b c_spec.rb" tag:smoke))

    [ "spec/b c_spec.rb", "spec/100%_spec.rb", "spec/under_score_spec.rb" ].each do |path|
      expect(parse(filter.to_query(file: path)).file).to eq(path)
    end
  end

  it "builds the matching Explore query" do
    filter = parse("branch:dev tag:smoke file:spec/a_spec.rb")
    expect(filter.explore_query(sort: "duration")).to eq("file:spec/a_spec.rb branch:dev tag:smoke since:30d sort:duration")
    expect(filter.explore_query(flaky: true)).to eq("file:spec/a_spec.rb branch:dev tag:smoke is:flaky since:30d")
    expect(Search::Filter.parse(filter.explore_query(sort: "failures")).notices).to eq([])
  end
end
