require "rails_helper"

RSpec.describe Search::Filter do
  def parse(query) = described_class.parse(query)

  describe ".parse" do
    it "reads every key" do
      f = parse('login name:Checkout file:spec/cart error:"Timeout error" status:failed,skipped branch:release ' \
                "tag:smoke is:flaky since:30d sort:duration")
      expect(f).to have_attributes(text: [ "login" ], name: "Checkout", file: "spec/cart", error: "Timeout error",
                                   statuses: %w[failed skipped], branch: "release", tags: [ "smoke" ], flaky: true,
                                   since: "30d", sort: "duration", notices: [])
    end

    it "uses defaults for an empty query" do
      expect(parse("")).to have_attributes(text: [], statuses: [], tags: [], flaky: false, since: "7d", sort: nil, branch: nil)
      expect(parse("")).to eq(described_class.new)
    end

    it "treats keys case-insensitively and keeps branch case" do
      expect(parse("STATUS:Failed Branch:Feature/X IS:FLAKY")).to have_attributes(statuses: [ "failed" ], branch: "Feature/X", flaky: true)
    end

    it "keeps quoted phrases whole, and an unclosed quote runs to the end" do
      expect(parse('"user signs in" cart').text).to eq([ "user signs in", "cart" ])
      expect(parse('error:"Net::Read timed').error).to eq("Net::Read timed")
    end

    it "treats a word with :: as text, not a filter" do
      f = parse("Net::ReadTimeout")
      expect(f.text).to eq([ "Net::ReadTimeout" ])
      expect(f.notices).to eq([])
    end

    it "ANDs repeated tags, splits tags on commas and takes the last status and branch" do
      f = parse("tag:Smoke tag:login,api status:failed status:passed branch:a branch:b")
      expect(f).to have_attributes(tags: %w[smoke login api], statuses: [ "passed" ], branch: "b")
    end

    it "orders statuses canonically and drops duplicates" do
      expect(parse("status:skipped,failed,failed").statuses).to eq(%w[failed skipped])
    end

    it "ignores unknown keys and bad values with notices" do
      f = parse("foo:bar status:green,failed since:2y sort:fast is:slow name:")
      expect(f.statuses).to eq([ "failed" ])
      expect(f.since).to eq("7d")
      expect(f.sort).to be_nil
      expect(f.name).to be_nil
      expect(f.notices).to eq([
        'Ignored "foo:bar": unknown filter',
        'Ignored "status:green": unknown status',
        'Ignored "since:2y": use 24h, 7d, 30d or 90d',
        'Ignored "sort:fast": use failures, recent, duration or name',
        'Ignored "is:slow": use is:flaky or is:quarantined',
        'Ignored "name:": empty value'
      ])
    end

    it "caps the query length, the term count and each value" do
      long = parse("a" * 600)
      expect(long.text.first.length).to eq(100)
      expect(long.notices).to include("Only the first 500 characters are used", "Shortened text: values are at most 100 characters")

      many = parse((1..12).map { "w#{_1}" }.join(" "))
      expect(many.text).to eq((1..10).map { "w#{_1}" })
      expect(many.notices).to eq([ "Only the first 10 terms are used" ])
    end

    it "removes stray quote characters from values" do
      expect(parse('name:a"b').name).to eq("ab")
    end

    it "reads status:quarantined and is:quarantined and prints them back" do
      f = parse("status:quarantined,failed is:quarantined is:flaky")
      expect(f).to have_attributes(statuses: %w[failed quarantined], quarantined: true, flaky: true, notices: [])
      expect(f.to_query).to eq("status:failed,quarantined is:flaky is:quarantined")
      expect(f).to be_narrowed
    end
  end

  describe "#to_query and round trips" do
    # A local, not a constant: constants defined in a block leak into the top level.
    filters = [
      {},
      { text: [ "login", "user signs in", "status:failed", "Net::ReadTimeout" ] },
      { name: "Checkout flow", file: "spec/cart_spec.rb", error: "Timeout" },
      { statuses: %w[failed pending], branch: "feature/x", tags: [ "smoke", "slow test" ] },
      { flaky: true, since: "90d", sort: "recent" },
      { statuses: %w[quarantined], quarantined: true, flaky: true },
      { name: "100%_done" }
    ]

    it "prints a canonical query" do
      f = described_class.new(text: [ "a b", "c" ], statuses: %w[failed], tags: [ "smoke" ], flaky: true, since: "30d", sort: "name", branch: "main")
      expect(f.to_query).to eq('"a b" c status:failed branch:main tag:smoke is:flaky since:30d sort:name')
    end

    it "parses its own query back to an equal filter" do
      filters.each do |attrs|
        f = described_class.new(**attrs)
        expect(parse(f.to_query)).to eq(f), "round trip failed for #{attrs.inspect}: #{f.to_query}"
      end
    end

    it "reads its own params back to an equal filter" do
      filters.each do |attrs|
        f = described_class.new(**attrs)
        expect(described_class.from_params(f.to_params)).to eq(f), "params round trip failed for #{attrs.inspect}"
      end
    end
  end

  describe ".from_params" do
    it "reads the fields form" do
      f = described_class.from_params({ "text" => 'cart "signs in"', "name" => " Login ", "statuses" => %w[failed bogus],
                                        "tags" => "Smoke, slow test,", "flaky" => "1", "since" => "30d", "sort" => "name",
                                        "branch" => "release" })
      expect(f).to have_attributes(text: [ "cart", "signs in" ], name: "Login", statuses: [ "failed" ],
                                   tags: [ "smoke", "slow test" ], flaky: true, since: "30d", sort: "name", branch: "release")
    end

    it "drops the default branch and the level's default sort, and falls back on bad values" do
      f = described_class.from_params({ "branch" => "main", "sort" => "failures", "since" => "2y" }, default_branch: "main", level: "tests")
      expect(f).to have_attributes(branch: nil, sort: nil, since: "7d")
      expect(described_class.from_params({ "sort" => "recent" }, level: "results").sort).to be_nil
    end

    it "reads the quarantined checkbox" do
      expect(described_class.from_params({ "quarantined" => "1" }).quarantined).to be(true)
      expect(described_class.from_params({ "quarantined" => "0" }).quarantined).to be(false)
    end
  end

  describe "#sort_for" do
    it "defaults per level and maps failures to recent on results" do
      expect(described_class.new.sort_for("tests")).to eq("failures")
      expect(described_class.new.sort_for("results")).to eq("recent")
      expect(described_class.new(sort: "failures").sort_for("results")).to eq("recent")
      expect(described_class.new(sort: "name").sort_for("results")).to eq("name")
    end
  end

  it "computes the range start" do
    now = Time.zone.parse("2026-10-24 12:00:00")
    expect(described_class.new(since: "24h").range_start(now)).to eq(now - 24.hours)
  end

  it "knows when it narrows the search" do
    expect(described_class.new(branch: "x", since: "30d", sort: "name")).not_to be_narrowed
    expect(described_class.new(tags: [ "smoke" ])).to be_narrowed
  end
end
