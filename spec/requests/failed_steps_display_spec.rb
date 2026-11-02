require "rails_helper"

RSpec.describe "Failed steps display", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:run) { create(:run, project: project) }
  let(:items) do
    [ { "id" => "s1", "title" => "Open https://shop.test/login" }, { "id" => "s2", "title" => "Type \"ana@shop.test\" into Email" },
      { "id" => "s3", "title" => "Click \"Save\"" }, { "id" => "s4", "title" => "See \"Welcome\"" } ]
  end

  before { sign_in(user) }

  def failing_result(steps:, status: "failed")
    create(:test_result, run: run, status: status, failure_message: "boom", steps: steps,
                         test_case: create(:test_case, project: project, full_name: "Login saves"))
  end

  def page
    get project_run_path(project, run)
    Nokogiri::HTML(response.body)
  end

  def testids(doc, id)
    doc.css("[data-testid=#{id}]")
  end

  it "marks passed, failed and not-run steps" do
    failing_result(steps: { "items" => items, "failed" => 2 })
    doc = page

    expect(testids(doc, "steps-headline").text.squish).to eq("Failed at step 3: Click \"Save\"")
    expect(testids(doc, "step-passed").size).to eq(2)
    expect(testids(doc, "step-failed").size).to eq(1)
    expect(testids(doc, "step-failed").text).to include("Click \"Save\"", "boom")
    expect(testids(doc, "step-not-run").size).to eq(1)
    expect(testids(doc, "step-not-run").text).to include("See \"Welcome\"", "Not run")
  end

  it "says when it couldn't tell which step failed" do
    failing_result(steps: { "items" => items, "failed" => nil })
    doc = page

    expect(doc.text).to include("Couldn't tell which step failed")
    expect(testids(doc, "step").size).to eq(4)
    expect(testids(doc, "step-failed")).to be_empty
    expect(testids(doc, "steps-headline")).to be_empty
    expect(doc.text).to include("boom")
  end

  it "escapes step titles" do
    failing_result(steps: { "items" => [ { "id" => "s1", "title" => "<script>x</script>" } ], "failed" => 0 })
    doc = page

    expect(testids(doc, "step-failed").text).to include("<script>x</script>")
    expect(doc.css("script").map(&:text)).not_to include("x")
  end

  it "shows steps on a quarantined result" do
    failing_result(status: "quarantined", steps: { "items" => items, "failed" => 0 })
    expect(testids(page, "step-failed").size).to eq(1)
  end

  it "leaves the card unchanged without steps" do
    failing_result(steps: nil)
    doc = page

    expect(doc.css("[data-testid^=step]")).to be_empty
    expect(doc.text).not_to include("Steps")
    expect(doc.text).to include("boom")
  end
end
