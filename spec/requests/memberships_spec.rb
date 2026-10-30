require "rails_helper"

RSpec.describe "Memberships", type: :request do
  let(:org) { create(:organization, name: "Acme") }
  let(:user) { create(:user) }

  def join(role, as: create(:user))
    create(:membership, organization: org, user: as, role: role)
  end

  describe "index" do
    %w[owner admin member viewer].each do |role|
      it "shows the members to a #{role}" do
        join(role, as: user)
        other = join("member")
        sign_in(user)
        get organization_memberships_path(org)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(other.user.email_address)
      end
    end

    it "shows no controls to a member except Leave on their own row" do
      join("member", as: user)
      join("viewer")
      sign_in(user)
      get organization_memberships_path(org)
      expect(response.body).not_to include("Remove", "Update")
      expect(response.body).to include("Leave")
    end

    it "shows a viewer no Update or Remove controls" do
      join("viewer", as: user)
      join("member")
      sign_in(user)
      get organization_memberships_path(org)
      expect(response.body).not_to include("Remove", "Update")
    end

    it "hides Leave for the personal owner on their personal organization" do
      sign_in(user)
      get organization_memberships_path(user.personal_organization)
      expect(response.body).not_to include("Leave")
    end

    it "offers admins only non-owner roles and no controls on owner rows" do
      join("admin", as: user)
      owner = join("owner")
      member = join("member")
      sign_in(user)
      get organization_memberships_path(org)
      body = Nokogiri::HTML(response.body)
      expect(body.css("##{ActionView::RecordIdentifier.dom_id(owner)} select")).to be_empty
      options = body.css("##{ActionView::RecordIdentifier.dom_id(member)} option").map(&:text)
      expect(options).to eq(%w[admin member viewer])
    end

    it "offers owners the owner role" do
      join("owner", as: user)
      member = join("member")
      sign_in(user)
      get organization_memberships_path(org)
      options = Nokogiri::HTML(response.body).css("##{ActionView::RecordIdentifier.dom_id(member)} option").map(&:text)
      expect(options).to include("owner")
    end

    it "404s for non-members" do
      sign_in(user)
      get organization_memberships_path(org)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "update" do
    it "changes a role" do
      join("admin", as: user)
      target = join("member")
      sign_in(user)
      patch organization_membership_path(org, target), params: { membership: { role: "viewer" } }
      expect(response).to redirect_to(organization_memberships_path(org))
      expect(target.reload.role).to eq("viewer")
    end

    it "maps Forbidden to 403" do
      join("admin", as: user)
      owner = join("owner")
      sign_in(user)
      patch organization_membership_path(org, owner), params: { membership: { role: "member" } }
      expect(response).to have_http_status(:forbidden)
      expect(owner.reload.role).to eq("owner")
      expect(response.body).to include("You need the owner role or higher to do this.")
    end

    it "404s for a membership of another organization" do
      join("owner", as: user)
      foreign = create(:membership, organization: create(:organization), role: "member")
      sign_in(user)
      patch organization_membership_path(org, foreign), params: { membership: { role: "viewer" } }
      expect(response).to have_http_status(:not_found)
      delete organization_membership_path(org, foreign)
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.role).to eq("member")
    end

    it "403s for a member" do
      join("member", as: user)
      target = join("viewer")
      sign_in(user)
      patch organization_membership_path(org, target), params: { membership: { role: "admin" } }
      expect(response).to have_http_status(:forbidden)
    end

    it "blocks the only owner demoting themselves (Review Focus 4)" do
      mine = join("owner", as: user)
      sign_in(user)
      patch organization_membership_path(org, mine), params: { membership: { role: "admin" } }
      expect(response).to redirect_to(organization_memberships_path(org))
      expect(flash[:alert]).to eq("An organization needs at least one owner")
      expect(mine.reload.role).to eq("owner")
    end

    it "rejects a role of superadmin (Review Focus 5)" do
      join("owner", as: user)
      target = join("member")
      sign_in(user)
      patch organization_membership_path(org, target), params: { membership: { role: "superadmin" } }
      expect(flash[:alert]).to be_present
      expect(target.reload.role).to eq("member")
    end

    it "404s for non-members" do
      target = join("member")
      sign_in(user)
      patch organization_membership_path(org, target), params: { membership: { role: "viewer" } }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "destroy" do
    it "removes a member" do
      join("admin", as: user)
      target = join("viewer")
      sign_in(user)
      expect { delete organization_membership_path(org, target) }.to change(Membership, :count).by(-1)
      expect(response).to redirect_to(organization_memberships_path(org))
    end

    it "maps Forbidden to 403" do
      join("admin", as: user)
      owner = join("owner")
      sign_in(user)
      expect { delete organization_membership_path(org, owner) }.not_to change(Membership, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "blocks the only owner leaving (Review Focus 4)" do
      mine = join("owner", as: user)
      sign_in(user)
      expect { delete organization_membership_path(org, mine) }.not_to change(Membership, :count)
      expect(response).to redirect_to(organization_memberships_path(org))
      expect(flash[:alert]).to eq("An organization needs at least one owner")
    end

    it "lets a member leave" do
      join("owner")
      mine = join("member", as: user)
      sign_in(user)
      delete organization_membership_path(org, mine)
      expect(response).to redirect_to(organizations_path)
      expect(Membership.exists?(mine.id)).to be(false)
    end

    it "blocks the personal owner leaving" do
      personal = user.personal_organization
      mine = personal.memberships.find_by!(user: user)
      sign_in(user)
      delete organization_membership_path(personal, mine)
      expect(flash[:alert]).to eq("You can't leave your personal organization")
      expect(Membership.exists?(mine.id)).to be(true)
    end
  end
end
