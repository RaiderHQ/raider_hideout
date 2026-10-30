require "rails_helper"

RSpec.describe "Build gate display", type: :request do
  include ActionView::RecordIdentifier

  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:build) { create(:build, project: project, branch: "feature") }

  before { sign_in(user) }

  def verdict!(target, status, rules = {})
    target.update_columns(gate_status: status, gate_result: JSON.generate("rules" => rules), gate_evaluated_at: Time.current)
  end

  def build_page
    get project_build_path(project, build)
    Nokogiri::HTML(response.body)
  end

  # PILL_BASE uppercases the text with CSS only, so the markup keeps its case; match loosely anyway.
  it "shows a red badge and one row per rule with threshold, actual, outcome and where it came from" do
    main = create(:build, project: project, branch: "main", created_at: 1.day.ago)
    build.update_columns(baseline_build_id: main.id, baseline_assigned_at: Time.current)
    verdict!(build, "failed", "pass_rate" => { "min" => 98, "actual" => 96, "outcome" => "failed" },
                              "new_failures" => { "outcome" => "skipped", "reason" => "no baseline build on main" },
                              "new_flaky" => { "count" => 1, "outcome" => "failed" })

    html = build_page

    badge = html.at_css("h1 [data-testid=gate-badge]")
    expect(badge.text).to match(/\AGate failed\z/i)
    expect(badge["class"]).to include("text-status-err")
    expect(html.at_css("[data-testid=gate-panel] h2").text).to eq("Quality gate")
    rows = html.css("[data-testid=gate-panel] [data-gate-rule]")
    expect(rows.map { |row| [ row["data-gate-rule"], row["data-gate-outcome"] ] })
      .to eq([ %w[pass_rate failed], %w[new_failures skipped], %w[new_flaky failed] ])
    expect(rows.map { |row| row.css("td").map { |td| td.text.squish } }).to eq([
      [ "Minimum pass rate", "≥ 98%", "96%", "✗ 96% < 98%" ],
      [ "No new failures", "0", "–", "– no baseline build on main" ],
      [ "No new flaky tests", "0", "1", "✗ 1 new flaky test" ]
    ])
    expect(rows.map { |row| row.at_css("a")["href"] })
      .to eq([ "#results", "#comparison", project_flaky_tests_path(project, branch: "feature") ])
    expect(html.at_css("#results [data-testid=build-tile]")).to be_present
    expect(html.at_css("#comparison")).to be_present
  end

  it "shows a skipped new-failures rule without a #comparison link when the page has no comparison section" do
    verdict!(build, "failed", "new_failures" => { "outcome" => "skipped", "reason" => "no baseline build on main" },
                              "new_flaky" => { "count" => 1, "outcome" => "failed" })

    html = build_page

    expect(html.at_css("#comparison")).to be_nil
    row = html.at_css("[data-testid=gate-panel] [data-gate-rule=new_failures]")
    expect(row.css("td").first.text.squish).to eq("No new failures")
    expect(row.at_css("a")).to be_nil
    expect(html.at_css("[data-testid=gate-panel] [data-gate-rule=new_flaky] a")["href"])
      .to eq(project_flaky_tests_path(project, branch: "feature"))
  end

  it "shows a green badge for a passed gate" do
    verdict!(build, "passed", "pass_rate" => { "min" => 90, "actual" => 100, "outcome" => "passed" })
    badge = build_page.at_css("[data-testid=gate-badge]")
    expect(badge.text).to match(/\AGate passed\z/i)
    expect(badge["class"]).to include("text-status-ok")
  end

  it "shows a grey pending badge and no panel only when the project has an enabled rule" do
    expect(build_page.at_css("[data-testid=gate-badge]")).to be_nil
    create(:gate_rule, project: project, no_new_flaky: true)
    html = build_page
    expect(html.at_css("[data-testid=gate-badge]").text).to match(/\AGate pending\z/i)
    expect(html.at_css("[data-testid=gate-badge]")["class"]).to include("text-neutral-mid")
    expect(html.at_css("[data-testid=gate-panel]")).to be_nil
  end

  it "shows nothing for none, even after a rule is turned on" do
    verdict!(build, "none")
    create(:gate_rule, project: project, min_pass_rate: 98)
    html = build_page
    expect(html.at_css("[data-testid=gate-badge]")).to be_nil
    expect(html.at_css("[data-testid=gate-panel]")).to be_nil
  end

  it "shows the gate column on the builds list: ✓, ✗, · for pending and empty for none" do
    passed = create(:build, project: project)
    failed = create(:build, project: project)
    pending = create(:build, project: project)
    none = create(:build, project: project)
    verdict!(passed, "passed")
    verdict!(failed, "failed")
    verdict!(none, "none")

    get project_builds_path(project)
    html = Nokogiri::HTML(response.body)
    cell = ->(target) { html.at_css("##{dom_id(target)} [data-testid=gate-cell]") }

    expect([ passed, failed, pending ].map { |target| [ cell.call(target).text, cell.call(target)["title"] ] })
      .to eq([ [ "✓", "Gate passed" ], [ "✗", "Gate failed" ], [ "·", "Gate pending" ] ])
    expect(cell.call(none).text).to eq("")
    expect(cell.call(none)["title"]).to be_nil
  end
end
