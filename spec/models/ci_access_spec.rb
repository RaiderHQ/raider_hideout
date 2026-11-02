require "rails_helper"

RSpec.describe CiAccess do
  let(:project) { create(:project) }
  let(:token) { "ghp_#{'a' * 36}" }

  def build_access(value) = described_class.new(project: project, token: value, token_saved_at: Time.current)

  it "accepts fine-grained and classic token formats" do
    expect(build_access("github_pat_#{'A1_' * 7}")).to be_valid
    expect(build_access(token)).to be_valid
  end

  it "rejects malformed tokens" do
    [ "github_pat_#{'a' * 19}", "ghp_#{'a' * 35}", "ghp_#{'a' * 37}", "ghp_#{'a' * 35} ", "ghp_ #{'a' * 35}",
      "ghp_#{'a' * 36}\n", "#{token}\nx", "", nil ].each do |value|
      access = build_access(value)
      expect(access).not_to be_valid, value.inspect
      expect(access.errors[:base]).to eq([ "That doesn't look like a GitHub token." ])
    end
  end

  it "stores the token encrypted" do
    build_access(token).save!
    raw = described_class.connection.select_value("SELECT token FROM ci_accesses")
    expect(raw).not_to include(token)
    expect(described_class.last.token).to eq(token)
  end

  it "keeps the token out of inspect and attributes" do
    access = build_access(token)
    access.save!
    expect(access.inspect).not_to include(token)
    expect(access.attributes.to_s).not_to include(token)
    expect(access.attributes.inspect).not_to include(token)
    expect(described_class.find(access.id).inspect).not_to include(token)
  end

  it "redacts the token from text" do
    access = build_access(token)
    expect(access.redact("bad credentials #{token} and #{token}")).to eq("bad credentials [token] and [token]")
    expect(access.redact(nil)).to eq("")
  end

  it "is unique per project" do
    build_access(token).save!
    expect(build_access(token)).not_to be_valid
  end
end
