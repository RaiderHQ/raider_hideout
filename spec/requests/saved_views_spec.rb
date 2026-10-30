require "rails_helper"

RSpec.describe "Saved views", type: :request do
  let(:owner) { create(:user) }
  let(:organization) { create(:organization).tap { create(:membership, organization: _1, user: owner, role: "owner") } }
  let(:project) { create(:project, organization: organization) }

  def member(role)
    create(:user).tap { create(:membership, organization: organization, user: _1, role: role) }
  end

  def create_view(**attrs)
    post project_saved_views_path(project), params: { saved_view: { name: "Smoke", level: "tests", q: "tag:Smoke  status:failed" }.merge(attrs) }
  end

  describe "create" do
    it "saves a personal view with the canonical query and opens it" do
      user = member("viewer")
      sign_in(user)
      create_view
      view = SavedView.last
      expect(view).to have_attributes(user: user, name: "Smoke", query: "status:failed tag:smoke", level: "tests", shared: false)
      expect(response).to redirect_to(project_explore_path(project, view: view.id))
    end

    it "lets a member share, but not a viewer" do
      sign_in(member("member"))
      create_view(shared: "1")
      expect(SavedView.last).to be_shared

      sign_in(member("viewer"))
      expect { create_view(name: "Other", shared: "1") }.not_to change(SavedView, :count)
      expect(flash[:alert]).to eq("You need the member role or higher to share views.")
    end

    it "redirects back with the error for an invalid view" do
      sign_in(owner)
      create_view(name: "")
      expect(response).to redirect_to(project_explore_path(project, level: "tests", q: "status:failed tag:smoke"))
      expect(flash[:alert]).to eq("Name can't be blank")
    end
  end

  describe "update and destroy" do
    let(:author) { member("member") }
    let!(:personal) { create(:saved_view, project: project, user: author, name: "Mine") }
    let!(:shared) { create(:saved_view, project: project, user: author, name: "Team", shared: true) }

    it "lets the author rename, overwrite, unshare and delete" do
      sign_in(author)
      patch project_saved_view_path(project, personal), params: { saved_view: { name: "Renamed", level: "results", q: "is:flaky" } }
      expect(personal.reload).to have_attributes(name: "Renamed", level: "results", query: "is:flaky")
      patch project_saved_view_path(project, shared), params: { saved_view: { shared: "0" } }
      expect(shared.reload).not_to be_shared
      delete project_saved_view_path(project, personal)
      expect(SavedView.exists?(personal.id)).to be(false)
    end

    it "404s on someone else's personal view, even for an admin" do
      sign_in(member("admin"))
      patch project_saved_view_path(project, personal), params: { saved_view: { name: "X" } }
      expect(response).to have_http_status(:not_found)
      delete project_saved_view_path(project, personal)
      expect(response).to have_http_status(:not_found)
      get project_explore_path(project, view: personal.id)
      expect(response).to have_http_status(:not_found)
    end

    it "forbids a member or viewer from editing another user's shared view" do
      %w[member viewer].each do |role|
        sign_in(member(role))
        patch project_saved_view_path(project, shared), params: { saved_view: { name: "X" } }
        expect(response).to have_http_status(:forbidden)
        delete project_saved_view_path(project, shared)
        expect(response).to have_http_status(:forbidden)
      end
      expect(shared.reload.name).to eq("Team")
    end

    it "lets an admin edit and delete another user's shared view" do
      sign_in(member("admin"))
      patch project_saved_view_path(project, shared), params: { saved_view: { name: "Team views" } }
      expect(shared.reload.name).to eq("Team views")
      delete project_saved_view_path(project, shared)
      expect(SavedView.exists?(shared.id)).to be(false)
    end

    it "keeps a demoted author's shared view shared and editable, but blocks sharing more" do
      Membership.find_by!(user: author, organization: organization).update!(role: "viewer")
      sign_in(author)
      patch project_saved_view_path(project, shared), params: { saved_view: { name: "Still mine" } }
      expect(shared.reload).to have_attributes(name: "Still mine", shared: true)
      patch project_saved_view_path(project, personal), params: { saved_view: { shared: "1" } }
      expect(personal.reload).not_to be_shared
      expect(flash[:alert]).to eq("You need the member role or higher to share views.")
    end
  end

  it "404s for another organization's project" do
    sign_in(create(:user))
    create_view
    expect(response).to have_http_status(:not_found)
  end
end
