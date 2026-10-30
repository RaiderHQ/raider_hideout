require "rails_helper"

RSpec.describe ApiToken do
  let(:project) { create(:project) }

  it "issues a prefixed token and stores only its digest" do
    token, plain = described_class.issue!(project: project, name: "CI")
    expect(plain).to start_with("rdr_")
    expect(token.token_digest).to eq(described_class.digest(plain))
    expect(token.token_digest).not_to include(plain)
  end

  it "authenticates by plaintext and records last use" do
    token, plain = described_class.issue!(project: project, name: "CI")
    expect(described_class.authenticate(plain)).to eq(token)
    expect(token.reload.last_used_at).to be_present
  end

  it "rejects names longer than 100 characters" do
    token = described_class.new(project: project, name: "a" * 101, token_digest: "x")
    expect(token).not_to be_valid
    expect(token.errors[:name]).to be_present
  end

  it "rejects blank and unknown tokens" do
    expect(described_class.authenticate(nil)).to be_nil
    expect(described_class.authenticate("")).to be_nil
    expect(described_class.authenticate("rdr_nope")).to be_nil
  end

  it "rejects personal (rdp_) tokens, even one whose digest is stored here (Review Focus 2)" do
    personal = PersonalToken.issue!(user: create(:user), name: "laptop", expires_in_days: 90).last
    described_class.create!(project: project, name: "forged", token_digest: described_class.digest(personal))
    expect(described_class.authenticate(personal)).to be_nil
  end
end
