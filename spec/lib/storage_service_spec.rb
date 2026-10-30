require "rails_helper"
require "storage_service"

RSpec.describe StorageService do
  let(:s3) do
    { "ACTIVE_STORAGE_SERVICE" => "s3", "S3_BUCKET" => "attachments", "S3_ACCESS_KEY_ID" => "k", "S3_SECRET_ACCESS_KEY" => "s" }
  end

  it "defaults to the local Disk service when unset or blank" do
    expect(described_class.service({})).to eq("local")
    expect(described_class.service("ACTIVE_STORAGE_SERVICE" => "  ")).to eq("local")
  end

  it "treats s3 and the deprecated r2 as object storage" do
    expect(described_class.s3?("ACTIVE_STORAGE_SERVICE" => "s3")).to be(true)
    expect(described_class.s3?("ACTIVE_STORAGE_SERVICE" => "r2")).to be(true)
    expect(described_class.s3?({})).to be(false)
  end

  describe ".setting" do
    it "prefers the S3_ name and falls back to the R2_ one" do
      expect(described_class.setting("S3_BUCKET", "S3_BUCKET" => "new", "R2_BUCKET" => "old")).to eq("new")
      expect(described_class.setting("S3_BUCKET", "S3_BUCKET" => " ", "R2_BUCKET" => "old")).to eq("old")
      expect(described_class.setting("BACKUP_S3_ACCESS_KEY_ID", "BACKUP_ACCESS_KEY_ID" => "old")).to eq("old")
      expect(described_class.setting("S3_REGION", {})).to eq("")
    end
  end

  it "flags deprecated settings" do
    expect(described_class.deprecated?(s3)).to be(false)
    expect(described_class.deprecated?("ACTIVE_STORAGE_SERVICE" => "r2")).to be(true)
    expect(described_class.deprecated?(s3.merge("R2_ENDPOINT" => "https://acct.r2.cloudflarestorage.com"))).to be(true)
    expect(described_class.deprecated?("BACKUP_SECRET_ACCESS_KEY" => "x")).to be(true)
  end

  describe ".s3_options" do
    it "leaves the endpoint out for AWS and defaults the region to auto" do
      expect(described_class.s3_options(s3)).to eq(region: "auto", bucket: "attachments", access_key_id: "k",
                                                   secret_access_key: "s", force_path_style: false)
    end

    it "passes a custom endpoint and path-style addressing" do
      options = described_class.s3_options(s3.merge("S3_ENDPOINT" => "http://localhost:9000", "S3_FORCE_PATH_STYLE" => "true",
                                                    "S3_REGION" => "us-west-2"))
      expect(options).to include(endpoint: "http://localhost:9000", force_path_style: true, region: "us-west-2")
    end

    it "keeps path-style addressing on for the deprecated r2 service" do
      env = { "ACTIVE_STORAGE_SERVICE" => "r2", "R2_ENDPOINT" => "https://acct.r2.cloudflarestorage.com", "R2_BUCKET" => "a",
              "R2_ACCESS_KEY_ID" => "k", "R2_SECRET_ACCESS_KEY" => "s" }
      expect(described_class.s3_options(env)).to include(endpoint: "https://acct.r2.cloudflarestorage.com", bucket: "a",
                                                         force_path_style: true)
    end
  end

  describe ".backup_options" do
    it "uses its own keys and the attachments endpoint unless BACKUP_S3_ENDPOINT is set" do
      env = s3.merge("S3_ENDPOINT" => "https://storage.example.com", "BACKUP_S3_ACCESS_KEY_ID" => "bk",
                     "BACKUP_S3_SECRET_ACCESS_KEY" => "bs")
      expect(described_class.backup_options(env)).to eq(region: "auto", force_path_style: false, access_key_id: "bk",
                                                        secret_access_key: "bs", endpoint: "https://storage.example.com")
      expect(described_class.backup_options(env.merge("BACKUP_S3_ENDPOINT" => "https://backups.example.com",
                                                      "BACKUP_S3_REGION" => "eu-west-1")))
        .to include(endpoint: "https://backups.example.com", region: "eu-west-1")
    end

    it "reads the deprecated backup names" do
      env = { "R2_ENDPOINT" => "https://acct.r2.cloudflarestorage.com", "BACKUP_ACCESS_KEY_ID" => "bk", "BACKUP_SECRET_ACCESS_KEY" => "bs" }
      expect(described_class.backup_options(env)).to include(endpoint: "https://acct.r2.cloudflarestorage.com",
                                                             access_key_id: "bk", secret_access_key: "bs")
    end
  end

  describe ".s3_origin" do
    def origin(extra) = described_class.s3_origin(s3.merge(extra))

    it "matches the host the SDK presigns on" do
      expect(origin("S3_ENDPOINT" => "https://acct.r2.cloudflarestorage.com/", "S3_FORCE_PATH_STYLE" => "true"))
        .to eq("https://acct.r2.cloudflarestorage.com")
      expect(origin("S3_ENDPOINT" => "http://localhost:9000", "S3_FORCE_PATH_STYLE" => "true")).to eq("http://localhost:9000")
      expect(origin("S3_ENDPOINT" => "https://storage.example.com")).to eq("https://attachments.storage.example.com")
      expect(origin("S3_REGION" => "eu-central-1")).to eq("https://attachments.s3.eu-central-1.amazonaws.com")
      expect(origin("S3_REGION" => "us-east-1")).to eq("https://attachments.s3.amazonaws.com")
    end

    it "is nil for an unusable endpoint or the local service" do
      expect(origin("S3_ENDPOINT" => "not a url")).to be_nil
      expect(described_class.s3_origin({})).to be_nil
    end
  end
end
