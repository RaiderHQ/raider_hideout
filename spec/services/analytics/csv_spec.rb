require "rails_helper"

RSpec.describe Analytics::Csv do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-28 12:00:00") }
  let(:project) { create(:project, name: "Shop") }
  let(:test_url) { ->(test_case) { "http://example.test/t/#{test_case.id}" } }

  around { |example| travel_to(now) { example.run } }

  def table(list, query = "")
    CSV.parse(described_class.new(project, analytics_filter(query, project: project), list: list, test_url: test_url).to_csv)
  end

  it "names the file after the project slug, the list and the date" do
    csv = described_class.new(project, analytics_filter(project: project), list: "trend", test_url: test_url)
    expect(csv.filename).to eq("#{project.slug}-trend-2026-10-28.csv")
  end

  it "refuses an unknown list" do
    expect { described_class.new(project, analytics_filter(project: project), list: "bogus", test_url: test_url) }
      .to raise_error(ArgumentError)
  end

  it "guards cells a spreadsheet would run as formulas" do
    expect([ "=1+1", "+1", "-1", "@SUM(A1)", "\tx", "\rx" ].map { described_class.guard(_1) })
      .to eq([ "'=1+1", "'+1", "'-1", "'@SUM(A1)", "'\tx", "'\rx" ])
    expect([ "spec/a_spec.rb", 95, nil, true ].map { described_class.guard(_1) }).to eq([ "spec/a_spec.rb", "95", nil, "true" ])
  end

  it "writes a nil flip rate as a blank flaky cell" do
    test = create(:test_case, project: project, full_name: "T", file_path: "spec/a_spec.rb")
    create(:test_case_verdict, test_case: test, branch: "main", flaky: true, flip_rate: nil)

    expect(table("flaky").last[3]).to be_nil
  end

  it "writes failing tests with test_id, plain numbers, ISO times, booleans and url" do
    test = create(:test_case, project: project, full_name: "=HYPERLINK(\"x\")", file_path: "spec/a_spec.rb")
    search_result(test, status: "failed", at: 1.day.ago)

    expect(table("failing")).to eq([
      %w[test_id test file failures executed failure_rate last_failure flaky quarantined url],
      [ test.id.to_s, "'=HYPERLINK(\"x\")", "spec/a_spec.rb", "1", "1", "100", "2026-10-27T12:00:00Z", "false", "false",
        "http://example.test/t/#{test.id}" ]
    ])
  end

  it "keeps commas, quotes and newlines in a test name inside one cell (Review Focus 2)" do
    test = create(:test_case, project: project, full_name: %(Login, "remember me"\nthen -logout), file_path: "spec/a, b_spec.rb")
    search_result(test, status: "failed", at: 1.day.ago)

    row = table("failing").second
    expect(row.size).to eq(10)
    expect(row[1..2]).to eq([ %(Login, "remember me"\nthen -logout), "spec/a, b_spec.rb" ])
  end

  it "writes the trend with blank empty values" do
    rows = table("trend", "since:7d")

    expect(rows.first).to eq(%w[date executed failed failure_rate avg_test_duration_ms avg_build_duration_ms flaky_count])
    expect(rows.second).to eq([ "2026-10-21", "0", "0", nil, nil, nil, nil ])
    expect(rows.size).to eq(9)
  end
end
