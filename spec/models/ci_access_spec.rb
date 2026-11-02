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

  it "keeps the token out of inspect and serialization" do
    access = build_access(token)
    access.save!
    [ access, described_class.find(access.id) ].each do |record|
      expect(record.inspect).not_to include(token)
      expect(record.inspect).to include("[FILTERED]")
      expect(record.as_json.to_s).not_to include(token)
      expect(record.to_json).not_to include(token)
      expect(record.as_json).not_to have_key("token")
      expect(record.as_json(only: %i[token provider])).not_to have_key("token")
    end
  end

  it "redacts the token from text" do
    access = build_access(token)
    expect(access.redact("bad credentials #{token} and #{token}")).to eq("bad credentials [token] and [token]")
    expect(access.redact(nil)).to eq("")
  end

  it "masks token-shaped strings such as an echoed prefix" do
    access = build_access(token)
    expect(access.redact("got ghp_abcdefgh12 and github_pat_11ABCDEFG_x here")).to eq("got [token] and [token] here")
    expect(access.redact("short ghp_abc")).to eq("short ghp_abc")
  end

  it "is unique per project" do
    build_access(token).save!
    expect(build_access(token)).not_to be_valid
  end
end
