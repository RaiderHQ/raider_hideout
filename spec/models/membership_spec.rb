require "rails_helper"

RSpec.describe Membership do
  it "pins the role ranks" do
    expect(described_class::ROLES).to eq(%w[owner admin member viewer])
    expect(described_class::RANK).to eq("viewer" => 0, "member" => 1, "admin" => 2, "owner" => 3)
  end

  it "rejects an unknown role" do
    expect(build(:membership, role: "superuser").valid?).to be(false)
    expect(build(:membership, role: nil).valid?).to be(false)
  end

  it "allows one membership per user and organization" do
    existing = create(:membership)
    duplicate = build(:membership, organization: existing.organization, user: existing.user, role: "viewer")
    expect(duplicate.valid?).to be(false)
    expect(duplicate.errors[:user_id]).to be_present
    expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "compares roles with at_least?" do
    admin = build(:membership, role: "admin")
    expect(admin.at_least?("viewer")).to be(true)
    expect(admin.at_least?(:member)).to be(true)
    expect(admin.at_least?("admin")).to be(true)
    expect(admin.at_least?("owner")).to be(false)
    expect(build(:membership, role: "viewer").at_least?("member")).to be(false)
  end

  it "disconnects the user's cable connections when the membership is removed" do
    membership = create(:membership)
    connections = double(disconnect: true)
    allow(ActionCable.server.remote_connections).to receive(:where).with(current_user: membership.user).and_return(connections)
    membership.destroy!
    expect(connections).to have_received(:disconnect).with(reconnect: true)
  end
end
