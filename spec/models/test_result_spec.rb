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
