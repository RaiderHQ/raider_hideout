require "rails_helper"

RSpec.describe "Projects", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "creates a project and redirects to it" do
    post projects_path, params: { project: { name: "Shop" } }
    expect(response).to redirect_to(project_path("shop"))
    expect(user.projects.pluck(:name)).to eq([ "Shop" ])
  end

  it "lists only the current user's projects" do
    create(:project, owner: user, name: "Mine")
    create(:project, name: "Theirs")
    get projects_path
    expect(response.body).to include("Mine")
    expect(response.body).not_to include("Theirs")
  end

  it "404s for another user's project" do
    other = create(:project, name: "Secret")
    get project_path(other)
    expect(response).to have_http_status(:not_found)
  end
end
