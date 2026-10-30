require "rails_helper"

RSpec.describe "Expired data display", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:build) { create(:build, project: project, total_count: 4, passed_count: 3, failed_count: 1) }

  before { sign_in(user) }

  def notice
    Nokogiri::HTML(response.body).at_css("[data-testid=results-expired]")&.text&.strip
  end

  it "replaces a fully purged build's results with the notice and keeps its totals" do
    create(:run, project: project, build: build, results_purged_at: 1.day.ago)

    get project_build_path(project, build)

    expect(notice).to eq("Test results expired after 90 days. Totals are kept.")
    expect(response.body).to include(">4<", ">3<")
    expect(response.body).not_to include('data-testid="comparison"')
  end

  it "shows the some-shards notice above remaining results" do
    create(:run, project: project, build: build, results_purged_at: 1.day.ago)
    live = create(:run, project: project, build: build)
    create(:test_result, run: live, test_case: create(:test_case, project: project, full_name: "Still here"))

    get project_build_path(project, build)

    expect(notice).to eq("Some shards' results expired after 90 days.")
    expect(response.body).to include("Still here")
  end

  it "shows the notice on a purged run page" do
    run = create(:run, project: project, build: build, results_purged_at: 1.day.ago)
    get project_run_path(project, run)
    expect(notice).to eq("Test results expired after 90 days. Totals are kept.")
  end

  it "shows no notice when nothing expired" do
    create(:run, project: project, build: build)
    get project_build_path(project, build)
    expect(notice).to be_nil
  end

  it "marks failed and quarantined results whose attachments expired, and only those" do
    run = create(:run, project: project, build: build, attachments_purged_at: 1.day.ago)
    create(:test_result, run: run, status: "failed", test_case: create(:test_case, project: project, full_name: "Broke"))
    create(:test_result, run: run, status: "quarantined", test_case: create(:test_case, project: project, full_name: "Held"))
    create(:test_result, run: run, status: "passed", test_case: create(:test_case, project: project, full_name: "Fine"))

    get project_run_path(project, run)

    expired = Nokogiri::HTML(response.body).css("[data-testid=attachments-expired]")
    expect(expired.size).to eq(2)
    expect(expired.map { _1.text.strip }).to all(eq("Attachments expired after 30 days."))
  end

  it "says the baseline expired instead of listing every test as new" do
    baseline = create(:build, project: project, branch: "main")
    create(:run, project: project, build: baseline, results_purged_at: 1.day.ago)
    current = create(:build, project: project, branch: "feature", default_branch: "main", baseline_build: baseline,
                             baseline_assigned_at: Time.current)
    run = create(:run, project: project, build: current, branch: "feature")
    create(:test_result, run: run)
    allow_any_instance_of(Build).to receive(:ready_to_notify?).and_return(true)

    get project_build_path(project, current)

    comparison = Nokogiri::HTML(response.body).at_css("[data-testid=comparison]").text
    expect(comparison).to include("Baseline results expired — compared builds are older than 90 days.")
    expect(comparison).not_to include("New tests")
  end

  it "returns 404 for a test case removed as an orphan" do
    test_case = create(:test_case, project: project)
    id = test_case.id
    test_case.destroy!
    get project_test_case_path(project, id)
    expect(response).to have_http_status(:not_found)
  end
end
