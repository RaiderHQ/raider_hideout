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

  describe "Run tests settings" do
    def with_settings(**attrs) = build_access(token).tap { |access| access.assign_attributes(attrs) }

    it "accepts owner/name repositories and rejects anything else" do
      expect(with_settings(repository: "a/b")).to be_valid
      expect(with_settings(repository: "acme/shop-tests.v2")).to be_valid
      [ "a/b/c", "../x", "a", "a/", "/b", "a/..", "./b", "a b/c", "a/b?x", "a/%2F" ].each do |value|
        access = with_settings(repository: value)
        expect(access).not_to be_valid, value.inspect
        expect(access.errors[:repository]).to eq([ "Enter the repository as owner/name." ])
      end
    end

    it "accepts .yml and .yaml workflow files only" do
      expect(with_settings(workflow: "x.yml")).to be_valid
      expect(with_settings(workflow: "test_pipeline.yaml")).to be_valid
      [ "x.yml/..", "x", "x.json", "../x.yml", "a/x.yml", "x%2F.yml", "#{'a' * 101}.yml" ].each do |value|
        access = with_settings(workflow: value)
        expect(access).not_to be_valid, value.inspect
        expect(access.errors[:workflow]).to eq([ "Enter a workflow file name ending in .yml or .yaml." ])
      end
    end

    it "accepts input names only" do
      expect(with_settings(tag_input: "tags")).to be_valid
      expect(with_settings(tag_input: "_rspec-tags2")).to be_valid
      [ "1tags", "ta gs", "tags/x", "t.ags", "a" * 101 ].each do |value|
        access = with_settings(tag_input: value)
        expect(access).not_to be_valid, value.inspect
        expect(access.errors[:tag_input]).to eq([ "Use letters, numbers, - and _ for the input name." ])
      end
    end

    it "strips the settings and stores blanks as nil" do
      access = with_settings(repository: "  a/b ", workflow: " x.yml", tag_input: "   ")
      expect([ access.repository, access.workflow, access.tag_input ]).to eq([ "a/b", "x.yml", nil ])
    end

    it "splits the repository" do
      expect(with_settings(repository: "acme/shop").repository_parts).to eq(%w[acme shop])
      expect(with_settings(repository: nil).repository_parts).to be_nil
      expect(with_settings(repository: "a/b/c").repository_parts).to be_nil
    end

    it "is ready to run tests only with a token, a repository and a workflow" do
      expect(with_settings(repository: "a/b", workflow: "x.yml")).to be_run_tests_ready
      expect(with_settings(repository: "a/b")).not_to be_run_tests_ready
      expect(with_settings(workflow: "x.yml")).not_to be_run_tests_ready
      expect(with_settings(repository: "a/b", workflow: "x.yml", token: "nope")).not_to be_run_tests_ready
      expect(with_settings(repository: "a/b/c", workflow: "x.yml")).not_to be_run_tests_ready
    end

    it "detects the repository from the latest GitHub Actions build with a valid key" do
      access = build_access(token)
      expect(access.detected_repository).to be_nil
      create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:old/repo:1")
      create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:Acme/Shop:2")
      create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:../r:3")
      create(:build, project: project, provider: "other", ci_run_key: "github_actions:x/y:4")
      expect(access.detected_repository).to eq("Acme/Shop")
    end
  end
end
