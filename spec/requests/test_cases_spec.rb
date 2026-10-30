require "rails_helper"

RSpec.describe "Test case history", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:test_case) { create(:test_case, project: project, full_name: "Checkout pays") }

  before do
    create(:test_case_verdict, test_case: test_case, branch: "main", flaky: true, flaky_reason: "same_commit", flip_rate: 0.5)
  end

  before { sign_in(user) }

  it "shows recent results on the selected branch and the flaky reason" do
    %w[passed failed].each { |s| create(:test_result, test_case: test_case, status: s, run: create(:run, project: project, branch: "main")) }
    create(:test_result, test_case: test_case, status: "failed", run: create(:run, project: project, branch: "feature"))
    get project_test_case_path(project, test_case, branch: "main")
    expect(response.body).to include("Checkout pays", "Passed and failed on the same commit", "50%")
    expect(response.body.scan('data-history-dot').size).to eq(2)
  end

  it "renders the nil-branch history when results only exist without a branch" do
    create(:test_result, test_case: test_case, status: "failed", run: create(:run, project: project, branch: nil))
    get project_test_case_path(project, test_case)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("no branch")
    expect(response.body.scan('data-history-dot').size).to eq(1)
  end

  it "shows a row per branch verdict" do
    create(:test_case_verdict, test_case: test_case, branch: "feature", flaky: false, flip_rate: 0.0, sample_count: 3)
    get project_test_case_path(project, test_case)
    rows = Nokogiri::HTML(response.body).css("tr[data-verdict-row]").map { |tr| tr.css("td").map { |td| td.text.strip } }
    expect(rows).to eq([ [ "feature", "No", "–", "3" ], [ "main", "flaky", "Passed and failed on the same commit", "5" ] ])
  end

  it "labels a verdict that falls back to the default branch" do
    create(:run, project: project, branch: "feature")
    create(:test_result, test_case: test_case, status: "failed", run: create(:run, project: project, branch: "feature"))
    get project_test_case_path(project, test_case, branch: "feature")
    expect(response.body).to include("Passed and failed on the same commit (on main)")
  end

  it "404s for another project's test case" do
    get project_test_case_path(project, create(:test_case))
    expect(response).to have_http_status(:not_found)
  end
end
