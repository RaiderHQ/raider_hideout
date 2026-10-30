require "rails_helper"

RSpec.describe User do
  describe "#projects" do
    it "spans every organization the user belongs to and nothing else" do
      user = create(:user)
      team = create(:organization)
      create(:membership, organization: team, user: user, role: "viewer")
      mine = create(:project, owner: user)
      shared = create(:project, organization: team)
      create(:project, organization: create(:organization))

      expect(user.projects).to contain_exactly(mine, shared)
      expect(user.organizations).to contain_exactly(user.personal_organization, team)
    end
  end

  describe "#role_in" do
    it "returns the role in that organization" do
      user = create(:user)
      team = create(:organization)
      create(:membership, organization: team, user: user, role: "member")
      expect(user.role_in(team)).to eq("member")
      expect(user.role_in(user.personal_organization)).to eq("owner")
      expect(user.role_in(create(:organization))).to be_nil
    end
  end
end
