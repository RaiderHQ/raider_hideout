require "rails_helper"

RSpec.describe Organization do
  it "derives a unique slug from the name" do
    first = create(:organization, name: "Acme QA")
    second = create(:organization, name: "Acme QA")
    expect([ first.slug, second.slug ]).to eq(%w[acme-qa acme-qa-2])
    expect(first.to_param).to eq("acme-qa")
  end

  it "never takes a reserved slug" do
    expect(create(:organization, name: "New").slug).to eq("new-2")
    expect(create(:organization, name: "Edit").slug).to eq("edit-2")
    org = create(:organization)
    expect(org.update(slug: "edit")).to be(false)
    expect(org.errors[:slug]).to be_present
  end

  it "requires a name of at most 100 characters" do
    expect(build(:organization, name: "").valid?).to be(false)
    expect(build(:organization, name: "a" * 101).valid?).to be(false)
    expect(build(:organization, name: "a" * 100).valid?).to be(true)
  end

  describe ".create_personal!" do
    it "truncates the email local part so the name stays within 100 characters" do
      user = create(:user, email_address: "#{'b' * 90}@x.io", with_personal_organization: false)
      org = described_class.create_personal!(user)
      expect(org.name).to eq("#{'b' * 85}'s organization")
    end

    it "creates a personal organization owned by the user" do
      user = create(:user, email_address: "ana@x.io", with_personal_organization: false)
      org = described_class.create_personal!(user)
      expect(org).to be_persisted
      expect(org).to have_attributes(name: "ana's organization", personal: true, personal_owner_id: user.id)
      expect(org.memberships.pluck(:user_id, :role)).to eq([ [ user.id, "owner" ] ])
      expect(user.reload.personal_organization).to eq(org)
    end
  end

  describe "#role_for" do
    it "returns the user's role, or nil without a membership" do
      org = create(:organization)
      admin = create(:user)
      create(:membership, organization: org, user: admin, role: "admin")
      expect(org.role_for(admin)).to eq("admin")
      expect(org.role_for(create(:user))).to be_nil
      expect(org.role_for(nil)).to be_nil
    end
  end

  describe "#owners and #notification_recipients" do
    it "returns owners and admins, never members or viewers" do
      org = create(:organization)
      owner = create(:user, email_address: "owner@x.io")
      admin = create(:user, email_address: "admin@x.io")
      create(:membership, organization: org, user: owner, role: "owner")
      create(:membership, organization: org, user: admin, role: "admin")
      create(:membership, organization: org, user: create(:user, email_address: "member@x.io"), role: "member")
      create(:membership, organization: org, user: create(:user, email_address: "viewer@x.io"), role: "viewer")

      expect(org.owners).to eq([ owner ])
      expect(org.notification_recipients).to contain_exactly("owner@x.io", "admin@x.io")
    end
  end
end
