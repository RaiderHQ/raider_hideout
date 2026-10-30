require "rails_helper"

RSpec.describe "Runs", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }

  before { sign_in(user) }

  it "lists runs newest first with a branch filter" do
    create(:run, project: project, branch: "main", commit_message: "Old main")
    create(:run, project: project, branch: "feature", commit_message: "Feature work")
    get project_runs_path(project)
    expect(response.body.index("Feature work")).to be < response.body.index("Old main")
    get project_runs_path(project, branch: "main")
    expect(response.body).to include("Old main")
    expect(response.body).not_to include("Feature work")
  end

  it "404s for another user's project" do
    get project_runs_path(create(:project))
    expect(response).to have_http_status(:not_found)
  end

  it "shows the empty state when there are no runs" do
    get project_runs_path(project)
    expect(response.body).to include("No runs yet")
  end
end
