require "rails_helper"

RSpec.describe "Flaky tests", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }

  before { sign_in(user) }

  def flaky_on(branch, name, flip_rate: 0.3, flaky: true)
    test_case = create(:test_case, project: project, full_name: name)
    create(:test_case_verdict, test_case: test_case, branch: branch, flaky: flaky, flaky_reason: ("flips" if flaky),
                               flip_rate: flip_rate)
    test_case
  end

  it "lists the default branch's flaky verdicts by flip rate" do
    create(:build, project: project, branch: "feature", default_branch: "trunk")
    flaky_on("trunk", "Low flip", flip_rate: 0.2)
    flaky_on("trunk", "High flip", flip_rate: 0.6)
    flaky_on("trunk", "Stable", flaky: false)
    flaky_on("feature", "Feature only")

    get project_flaky_tests_path(project)

    expect(response.body.index("High flip")).to be < response.body.index("Low flip")
    expect(response.body).to include("Status flips often between runs", "60%")
    expect(response.body).not_to include("Stable", "Feature only")
    expect(response.body).to include('<option selected="selected" value="trunk">trunk</option>')
    hrefs = Nokogiri::HTML(response.body).css("a").select { |a| a.text.strip == "Quarantine" }.map { |a| a["href"] }
    expect(hrefs.first).to eq(project_test_case_path(project, TestCase.find_by!(full_name: "High flip"), branch: "trunk", anchor: "quarantine"))
  end

  it "filters by the branch param" do
    flaky_on("main", "Main flaky")
    flaky_on("feature", "Feature flaky")

    get project_flaky_tests_path(project, branch: "main")
    expect(response.body).to include("Main flaky")
    expect(response.body).not_to include("Feature flaky")

    get project_flaky_tests_path(project, branch: "feature")
    expect(response.body).to include("Feature flaky")
    expect(response.body).not_to include("Main flaky")
  end

  it "offers the branches that have any verdict" do
    flaky_on("feature", "Feature flaky")
    flaky_on("release", "Healed", flaky: false)
    create(:run, project: project, branch: "runs-only")
    flaky_on("elsewhere", "Other project").update!(project: create(:project))

    get project_flaky_tests_path(project)

    options = response.body.scan(/<option[^>]*value="([^"]*)"/).flatten
    expect(options).to eq(%w[feature main release])
  end

  it "404s for a project the user is not a member of" do
    get project_flaky_tests_path(create(:project))
    expect(response).to have_http_status(:not_found)
  end
end
