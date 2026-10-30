require "rails_helper"

RSpec.describe "Organizations", type: :request do
  let(:user) { create(:user) }
  let(:org) { create(:organization, name: "Acme") }

  def join(role, organization: org, as: user)
    create(:membership, organization: organization, user: as, role: role)
  end

  describe "create" do
    before { sign_in(user) }

    it "makes the creator the owner" do
      expect { post organizations_path, params: { organization: { name: "Newco" } } }.to change(Organization, :count).by(1)
      created = Organization.find_by!(name: "Newco")
      expect(response).to redirect_to(organization_path(created))
      expect(user.role_in(created)).to eq("owner")
      expect(created.personal).to be(false)
    end

    it "re-renders on a blank name" do
      expect { post organizations_path, params: { organization: { name: "" } } }.not_to change(Organization, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "cannot set personal or personal_owner_id through params" do
      post organizations_path, params: { organization: { name: "Sneaky", personal: true, personal_owner_id: user.id } }
      created = Organization.find_by!(name: "Sneaky")
      expect(created.personal).to be(false)
      expect(created.personal_owner_id).to be_nil
    end

    it "renders the new form" do
      get new_organization_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "index and header" do
    it "shows the user's role in each organization from one memberships query" do
      join("viewer")
      join("admin", organization: create(:organization, name: "Beta"))
      sign_in(user)
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("memberships") }
      ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get organizations_path }
      body = Nokogiri::HTML(response.body).text.squish
      expect(body).to include("Acme viewer", "Beta admin", "owner · personal")
      expect(queries.size).to be <= 2
    end

    it "lists the user's organizations and the header menu" do
      join("viewer")
      create(:organization, name: "Hidden")
      sign_in(user)
      get organizations_path
      expect(response.body).to include("Acme", ERB::Util.html_escape(user.personal_organization.name))
      expect(response.body).not_to include("Hidden")
      get projects_path
      expect(response.body).to include('id="organization-menu"', "Acme", "New organization")
    end
  end

  describe "show" do
    it "lists the organization's projects" do
      join("viewer")
      create(:project, organization: org, name: "Shop")
      create(:project, name: "Elsewhere")
      sign_in(user)
      get organization_path(org)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Shop")
      expect(response.body).not_to include("Elsewhere")
    end

    it "404s for non-members" do
      sign_in(user)
      get organization_path(org)
      expect(response).to have_http_status(:not_found)
    end

    it "shows New project only to member and above" do
      join("viewer")
      sign_in(user)
      get organization_path(org)
      expect(response.body).not_to include("New project")
      Membership.find_by!(user: user, organization: org).update!(role: "member")
      get organization_path(org)
      expect(response.body).to include("New project")
    end

    it "preselects the organization on the new project form" do
      join("member")
      sign_in(user)
      get new_project_path(organization_id: org.id)
      expect(response.body).to match(/<option selected="selected" value="#{org.id}">Acme/)
    end
  end

  describe "edit and update" do
    it "lets the owner rename" do
      join("owner")
      sign_in(user)
      get edit_organization_path(org)
      expect(response).to have_http_status(:ok)
      patch organization_path(org), params: { organization: { name: "Renamed" } }
      expect(response).to redirect_to(organization_path(org))
      expect(org.reload.name).to eq("Renamed")
    end

    it "forbids an admin" do
      join("admin")
      sign_in(user)
      get edit_organization_path(org)
      expect(response).to have_http_status(:forbidden)
      patch organization_path(org), params: { organization: { name: "Renamed" } }
      expect(response).to have_http_status(:forbidden)
      expect(org.reload.name).to eq("Acme")
    end

    it "cannot set personal or personal_owner_id through params" do
      join("owner")
      sign_in(user)
      patch organization_path(org), params: { organization: { name: "Acme", personal: true, personal_owner_id: user.id } }
      expect(org.reload.personal).to be(false)
      expect(org.personal_owner_id).to be_nil
    end
  end

  describe "destroy" do
    before { join("owner") }

    it "requires the typed name" do
      create(:project, organization: org)
      sign_in(user)
      expect { delete organization_path(org), params: { confirm_name: "nope" } }.not_to change(Organization, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Type the organization name to confirm deletion")
    end

    it "destroys the organization with projects, builds and channels, then redirects to the personal one" do
      project = create(:project, organization: org)
      build = create(:build, project: project)
      channel = create(:notification_channel, :email, project: project)
      sign_in(user)
      delete organization_path(org), params: { confirm_name: "Acme" }
      expect(response).to redirect_to(organization_path(user.personal_organization))
      expect(Organization.exists?(org.id)).to be(false)
      expect([ Project.exists?(project.id), Build.exists?(build.id), NotificationChannel.exists?(channel.id) ]).to all(be(false))
    end

    it "shows the wrong-name error by the delete form, not in the rename form" do
      sign_in(user)
      delete organization_path(org), params: { confirm_name: "nope" }
      page = Nokogiri::HTML(response.body)
      expect(page.css("div.bg-status-err-bg").map(&:text)).to eq([ "Type the organization name to confirm deletion" ])
      expect(page.at_css("div.bg-status-err-bg").parent.at_css("form[action='#{organization_path(org)}']")).to be_present
    end

    it "falls back to the organizations index without a personal organization" do
      lone = create(:user, with_personal_organization: false)
      create(:membership, organization: org, user: lone, role: "owner")
      sign_in(lone)
      delete organization_path(org), params: { confirm_name: "Acme" }
      expect(response).to redirect_to(organizations_path)
    end

    it "forbids admins" do
      other = create(:organization)
      join("admin", organization: other)
      sign_in(user)
      delete organization_path(other), params: { confirm_name: other.name }
      expect(response).to have_http_status(:forbidden)
      expect(Organization.exists?(other.id)).to be(true)
    end

    it "returns 403 for a personal organization and offers no delete button" do
      personal = user.personal_organization
      sign_in(user)
      get edit_organization_path(personal)
      expect(response.body).not_to include("Delete organization")
      delete organization_path(personal), params: { confirm_name: personal.name }
      expect(response).to have_http_status(:forbidden)
      expect(Organization.exists?(personal.id)).to be(true)
    end

    it "offers the delete button for a non-personal organization" do
      sign_in(user)
      get edit_organization_path(org)
      expect(response.body).to include("Delete organization")
    end
  end

  describe "projects index grouping" do
    it "groups by organization, personal first then alphabetical" do
      zed = create(:organization, name: "Zed")
      alpha = create(:organization, name: "Alpha")
      [ zed, alpha ].each { |o| join("member", organization: o) }
      create(:project, organization: zed, name: "Zproj")
      create(:project, organization: alpha, name: "Aproj")
      create(:project, owner: user, name: "Mine")
      sign_in(user)
      get projects_path
      body = response.body
      expect(body.index("Mine")).to be < body.index("Aproj")
      expect(body.index("Aproj")).to be < body.index("Zproj")
    end
  end

  describe "role resolution on organization pages" do
    it "uses the organization role even when a project slug equals the organization slug" do
      owned = create(:organization, name: "Clash")
      join("viewer", organization: owned)
      other = create(:organization)
      join("owner", organization: other)
      project = create(:project, organization: other, name: "Clash")
      expect(project.slug).to eq(owned.slug)
      sign_in(user)
      get edit_organization_path(owned)
      expect(response).to have_http_status(:forbidden)
      patch organization_path(owned), params: { organization: { name: "Taken" } }
      expect(response).to have_http_status(:forbidden)
      expect(owned.reload.name).to eq("Clash")
    end
  end
end
