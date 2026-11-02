require "rails_helper"

RSpec.describe TestResult do
  it "groups results for display with failed first, then quarantined, then the rest" do
    run = create(:run)
    passed_file = create(:test_case, project: run.project, full_name: "a passes", file_path: "spec/a_spec.rb")
    held_file = create(:test_case, project: run.project, full_name: "b held", file_path: "spec/b_spec.rb")
    held = create(:test_case, project: run.project, full_name: "c held", file_path: "spec/c_spec.rb")
    broke = create(:test_case, project: run.project, full_name: "z broke", file_path: "spec/c_spec.rb")
    fine = create(:test_case, project: run.project, full_name: "a fine", file_path: "spec/c_spec.rb")
    results = { passed_file => "passed", held_file => "quarantined", held => "quarantined", broke => "failed", fine => "passed" }
              .map { |kase, status| build(:test_result, run: run, test_case: kase, status: status) }

    grouped = TestResult.grouped_for_display(results)

    expect(grouped.map(&:first)).to eq(%w[spec/c_spec.rb spec/b_spec.rb spec/a_spec.rb])
    expect(grouped.first.last.map { _1.test_case.full_name }).to eq([ "z broke", "c held", "a fine" ])
  end

  describe ".normalized_comparisons" do
    let(:fixture) { JSON.parse(file_fixture("payloads/comparisons/run.json").read)["results"].first["comparisons"].first }
    let(:entry) { fixture.dup }

    def normalize(*entries) = TestResult.normalized_comparisons(entries)

    it "round-trips the reporter's entry unchanged" do
      expect(TestResult.normalized_comparisons([ fixture ])).to eq([ fixture ])
    end

    it "is nil for a non-Array or an empty Array" do
      expect(TestResult.normalized_comparisons("x")).to be_nil
      expect(TestResult.normalized_comparisons({ "name" => "home" })).to be_nil
      expect(TestResult.normalized_comparisons(nil)).to be_nil
      expect(TestResult.normalized_comparisons([])).to be_nil
    end

    it "drops entries that are not usable" do
      bad = [ "x", entry.merge("status" => "weird"), entry.merge("name" => 7), entry.merge("name" => "../x"),
              entry.merge("name" => "a b"), entry.merge("name" => "<script>"), entry.merge("name" => "a" * 101) ]
      expect(normalize(*bad)).to be_nil
      expect(normalize(*bad, entry)).to eq([ fixture ])
    end

    it "accepts a name of exactly 100 characters" do
      expect(normalize(entry.merge("name" => "a/b-c_" + "a" * 94)).size).to eq(1)
    end

    {
      "diff_pixels" => [ -1, 1.5, "3" ], "max_diff_pixels" => [ -1, 2.5 ],
      "diff_ratio" => [ Float::NAN, Float::INFINITY, -0.1, "0.1" ], "threshold" => [ Float::NAN, "0.2" ],
      "max_diff_ratio" => [ "0.1", Float::INFINITY ],
      "expected_size" => [ [ 1, "x" ], [ 1, 2, 3 ], [ -1, 2 ], [ 1.5, 2 ], "1x2" ],
      "actual_size" => [ [ 1, 2, 3 ], [ 1 ], nil ],
      "baseline" => [ "a" * 301, 5 ]
    }.each do |field, values|
      values.each do |value|
        it "nils #{field} for #{value.inspect.first(30)}" do
          out = normalize(entry.merge(field => value)).first
          expect(out[field]).to be_nil
          expect(out["name"]).to eq("home")
        end
      end
    end

    it "bounds counts, sizes and ratios" do
      pick = ->(attrs) { normalize(entry.merge(attrs)).first }
      expect(pick.call("diff_pixels" => 10**20_000)["diff_pixels"]).to be_nil
      expect(pick.call("diff_pixels" => 10**9)["diff_pixels"]).to eq(10**9)
      expect(pick.call("diff_pixels" => 10**9 + 1)["diff_pixels"]).to be_nil
      expect(pick.call("max_diff_pixels" => 10**9 + 1)["max_diff_pixels"]).to be_nil
      expect(pick.call("expected_size" => [ 100_001, 1 ])["expected_size"]).to be_nil
      expect(pick.call("actual_size" => [ 1, 100_001 ])["actual_size"]).to be_nil
      expect(pick.call("actual_size" => [ 100_000, 100_000 ])["actual_size"]).to eq([ 100_000, 100_000 ])
      %w[diff_ratio threshold max_diff_ratio].each do |field|
        expect(pick.call(field => 1.0)[field]).to eq(1.0)
        expect(pick.call(field => 1.0000001)[field]).to be_nil
        expect(pick.call(field => 10**20_000)[field]).to be_nil
      end
    end

    it "turns negative zero into zero" do
      out = normalize(entry.merge("diff_ratio" => -0.0, "threshold" => -0.0)).first
      expect(out["diff_ratio"].to_s).to eq("0.0")
      expect(out["threshold"].to_s).to eq("0.0")
    end

    it "keeps zero values, integer ratios and a 300-character baseline" do
      out = normalize(entry.merge("diff_pixels" => 0, "diff_ratio" => 0, "baseline" => "b" * 300)).first
      expect(out).to include("diff_pixels" => 0, "diff_ratio" => 0, "baseline" => "b" * 300)
    end

    it "drops unknown keys and always returns the full key set" do
      out = normalize(entry.merge("extra" => 1)).first
      expect(out).not_to have_key("extra")
      expect(normalize({ "name" => "x", "status" => "passed" }).first.keys).to match_array(fixture.keys)
    end

    it "keeps the first 50, failed entries first, otherwise in order" do
      entries = Array.new(60) { |i| entry.merge("name" => "n#{i}", "status" => i >= 55 ? "failed" : "passed") }
      names = normalize(*entries).map { _1["name"] }
      expect(names.size).to eq(50)
      expect(names.first(5)).to eq(%w[n55 n56 n57 n58 n59])
      expect(names.drop(5)).to eq((0...45).map { "n#{_1}" })
    end
  end

  describe ".normalized_steps" do
    let(:items) { [ { "id" => "s1", "title" => "Open" }, { "id" => "s2", "title" => "Click \"Save\"" } ] }

    it "keeps a valid list and strips unknown keys" do
      value = { "items" => [ { "id" => "s1", "title" => "Open", "x" => 1 } ], "failed" => 0, "y" => 2 }
      expect(described_class.normalized_steps(value)).to eq("items" => [ { "id" => "s1", "title" => "Open" } ], "failed" => 0)
    end

    it "allows failed: null" do
      expect(described_class.normalized_steps("items" => items, "failed" => nil)).to eq("items" => items, "failed" => nil)
    end

    it "clips titles to 500 characters" do
      steps = described_class.normalized_steps("items" => [ { "id" => "s1", "title" => "x" * 501 } ], "failed" => 0)
      expect(steps["items"].first["title"].length).to eq(500)
    end

    it "accepts 200 items" do
      many = Array.new(200) { |i| { "id" => "s#{i}", "title" => "Step #{i}" } }
      expect(described_class.normalized_steps("items" => many, "failed" => 199)["items"].size).to eq(200)
    end

    it "returns nil for invalid input" do
      invalid = [
        nil, "x", [],
        { "items" => [], "failed" => nil },
        { "items" => "nope", "failed" => nil },
        { "items" => Array.new(201) { |i| { "id" => "s#{i}", "title" => "t" } }, "failed" => nil },
        { "items" => [ { "title" => "t" } ], "failed" => nil },
        { "items" => [ { "id" => "", "title" => "t" } ], "failed" => nil },
        { "items" => [ { "id" => 1, "title" => "t" } ], "failed" => nil },
        { "items" => [ { "id" => "s1", "title" => 5 } ], "failed" => nil },
        { "items" => [ "s1" ], "failed" => nil },
        { "items" => items, "failed" => true },
        { "items" => items, "failed" => 1.0 },
        { "items" => items, "failed" => -1 },
        { "items" => items, "failed" => 2 },
        { "items" => items, "failed" => "0" },
        { "items" => items }
      ]
      invalid.each { |value| expect(described_class.normalized_steps(value)).to be_nil, "expected nil for #{value.inspect}" }
    end
  end
end
