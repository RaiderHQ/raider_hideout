require "rails_helper"

RSpec.describe SavedView do
  let(:project) { create(:project) }
  let(:user) { create(:user) }

  it "validates name, query and level" do
    expect(build(:saved_view, project: project, user: user, name: " ")).not_to be_valid
    expect(build(:saved_view, project: project, user: user, name: "x" * 81)).not_to be_valid
    expect(build(:saved_view, project: project, user: user, query: "x" * 501)).not_to be_valid
    expect(build(:saved_view, project: project, user: user, level: "builds")).not_to be_valid
    expect(build(:saved_view, project: project, user: user, name: "  Smoke  ")).to be_valid.and(have_attributes(name: "Smoke"))
  end

  it "keeps names unique per user and project, ignoring case" do
    create(:saved_view, project: project, user: user, name: "Smoke")
    expect(build(:saved_view, project: project, user: user, name: "smoke")).not_to be_valid
    expect(build(:saved_view, project: project, user: create(:user), name: "Smoke")).to be_valid
    expect(build(:saved_view, project: create(:project), user: user, name: "Smoke")).to be_valid
  end

  it "keeps shared names unique within a project" do
    create(:saved_view, project: project, user: user, name: "Smoke on main", shared: true)
    other = build(:saved_view, project: project, user: create(:user), name: "SMOKE on main", shared: true)
    expect(other).not_to be_valid
    expect(other.errors[:name]).to include("is already used by a shared view")
    expect(build(:saved_view, project: project, user: create(:user), name: "Smoke on main", shared: false)).to be_valid
  end

  it "allows at most 50 views per user per project" do
    50.times { |i| create(:saved_view, project: project, user: user, name: "V#{i}") }
    extra = build(:saved_view, project: project, user: user, name: "One more")
    expect(extra).not_to be_valid
    expect(extra.errors[:base]).to include("You can have at most 50 views in a project")
  end

  it "shows a user their own views and the project's shared views" do
    mine = create(:saved_view, project: project, user: user)
    shared = create(:saved_view, project: project, user: create(:user), shared: true)
    create(:saved_view, project: project, user: create(:user))
    create(:saved_view, project: create(:project), user: user)
    expect(described_class.visible_to(user, project)).to contain_exactly(mine, shared)
  end

  it "is editable by its owner, and by admins when shared" do
    view = create(:saved_view, project: project, user: user)
    other = create(:user)
    expect(view.editable_by?(user, "viewer")).to be(true)
    expect(view.editable_by?(other, "owner")).to be(false)
    view.update!(shared: true)
    expect(view.editable_by?(other, "member")).to be(false)
    expect(view.editable_by?(other, "admin")).to be(true)
  end

  it "is deleted with its user and its project" do
    create(:saved_view, project: project, user: user)
    expect { user.destroy }.to change(described_class, :count).by(-1)
    create(:saved_view, project: project, user: create(:user))
    expect { project.destroy }.to change(described_class, :count).by(-1)
  end

  it "deletes personal views in the organization's projects when the membership goes, keeping shared ones" do
    org = create(:organization)
    membership = create(:membership, organization: org, user: user, role: "member")
    org_project = create(:project, organization: org)
    personal = create(:saved_view, project: org_project, user: user)
    shared = create(:saved_view, project: org_project, user: user, shared: true)
    elsewhere = create(:saved_view, project: project, user: user)

    membership.destroy

    expect(described_class.exists?(personal.id)).to be(false)
    expect(described_class.exists?(shared.id)).to be(true)
    expect(described_class.exists?(elsewhere.id)).to be(true)
  end
end
