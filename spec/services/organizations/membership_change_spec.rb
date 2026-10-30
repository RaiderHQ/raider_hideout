require "rails_helper"

RSpec.describe Organizations::MembershipChange do
  subject(:service) { described_class }

  let(:org) { create(:organization) }
  let(:forbidden) { Organizations::MembershipChange::Forbidden }
  let(:invalid) { Organizations::MembershipChange::Invalid }

  def join(role)
    create(:membership, organization: org, role: role)
  end

  describe ".update_role!" do
    it "lets an owner promote a member to owner" do
      owner = join("owner")
      target = join("member")
      service.update_role!(actor: owner.user, membership: target, role: "owner")
      expect(target.reload.role).to eq("owner")
    end

    it "lets an owner demote another owner when two exist" do
      owner = join("owner")
      other = join("owner")
      service.update_role!(actor: owner.user, membership: other, role: "member")
      expect(other.reload.role).to eq("member")
    end

    it "blocks demoting the last owner" do
      owner = join("owner")
      expect { service.update_role!(actor: owner.user, membership: owner, role: "admin") }
        .to raise_error(invalid, "An organization needs at least one owner")
      expect(owner.reload.role).to eq("owner")
    end

    it "forbids an admin from changing an owner or granting owner" do
      admin = join("admin")
      owner = join("owner")
      member = join("member")
      expect { service.update_role!(actor: admin.user, membership: owner, role: "member") }.to raise_error(forbidden)
      expect { service.update_role!(actor: admin.user, membership: member, role: "owner") }.to raise_error(forbidden)
      expect(owner.reload.role).to eq("owner")
      expect(member.reload.role).to eq("member")
    end

    it "lets an admin set admin, member or viewer" do
      admin = join("admin")
      member = join("member")
      service.update_role!(actor: admin.user, membership: member, role: "viewer")
      service.update_role!(actor: admin.user, membership: member, role: "admin")
      expect(member.reload.role).to eq("admin")
    end

    it "forbids a member or viewer from changing anyone" do
      target = join("member")
      %w[member viewer].each do |role|
        actor = join(role)
        expect { service.update_role!(actor: actor.user, membership: target, role: "viewer") }.to raise_error(forbidden)
      end
    end

    it "forbids a non-member" do
      target = join("member")
      expect { service.update_role!(actor: create(:user), membership: target, role: "viewer") }.to raise_error(forbidden)
    end

    it "stops a second owner demoting the personal owner" do
      user = create(:user)
      personal = user.personal_organization
      mine = personal.memberships.find_by!(user: user)
      other = create(:membership, organization: personal, role: "owner")
      expect { service.update_role!(actor: other.user, membership: mine, role: "admin") }
        .to raise_error(invalid, "The owner of a personal organization can't be demoted")
      expect(mine.reload.role).to eq("owner")
    end

    it "stops the personal owner demoting themselves" do
      user = create(:user)
      mine = user.personal_organization.memberships.find_by!(user: user)
      expect { service.update_role!(actor: user, membership: mine, role: "admin") }
        .to raise_error(invalid, "The owner of a personal organization can't be demoted")
      expect(mine.reload.role).to eq("owner")
    end

    it "rejects an unknown role" do
      owner = join("owner")
      target = join("member")
      expect { service.update_role!(actor: owner.user, membership: target, role: "superadmin") }
        .to raise_error(invalid)
      expect(target.reload.role).to eq("member")
    end
  end

  describe ".remove!" do
    it "lets an admin remove a viewer" do
      admin = join("admin")
      viewer = join("viewer")
      service.remove!(actor: admin.user, membership: viewer)
      expect(Membership.exists?(viewer.id)).to be(false)
    end

    it "forbids an admin from removing an owner" do
      admin = join("admin")
      owner = join("owner")
      expect { service.remove!(actor: admin.user, membership: owner) }.to raise_error(forbidden)
    end

    it "forbids a member from removing someone else" do
      member = join("member")
      viewer = join("viewer")
      expect { service.remove!(actor: member.user, membership: viewer) }.to raise_error(forbidden)
    end

    it "blocks removing the last owner" do
      owner = join("owner")
      expect { service.remove!(actor: owner.user, membership: owner) }
        .to raise_error(invalid, "An organization needs at least one owner")
      expect(Membership.exists?(owner.id)).to be(true)
    end

    it "lets any member leave a team organization" do
      join("owner")
      member = join("member")
      service.remove!(actor: member.user, membership: member)
      expect(Membership.exists?(member.id)).to be(false)
    end

    it "lets an owner leave when another owner exists" do
      owner = join("owner")
      join("owner")
      service.remove!(actor: owner.user, membership: owner)
      expect(Membership.exists?(owner.id)).to be(false)
    end

    it "stops the personal owner leaving their personal organization" do
      user = create(:user)
      membership = user.personal_organization.memberships.find_by!(user: user)
      expect { service.remove!(actor: user, membership: membership) }
        .to raise_error(invalid, "You can't leave your personal organization")
    end

    it "stops anyone removing the personal owner" do
      user = create(:user)
      personal = user.personal_organization
      membership = personal.memberships.find_by!(user: user)
      other_owner = create(:membership, organization: personal, role: "owner")
      expect { service.remove!(actor: other_owner.user, membership: membership) }
        .to raise_error(invalid, "You can't leave your personal organization")
    end
  end
end
