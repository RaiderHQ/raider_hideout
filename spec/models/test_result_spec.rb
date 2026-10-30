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
end
