require "rails_helper"
require "production_checks"

RSpec.describe ProductionChecks do
  let(:complete) { { "APP_HOST" => "hideout.example.com", "SMTP_ADDRESS" => "smtp.example.com", "MAILER_FROM" => "x@example.com" } }
  let(:err) { StringIO.new }
  let(:logger) { instance_double(Logger, warn: nil) }

  it "passes when everything is set" do
    expect(described_class.verify!(complete, logger: logger, err: err)).to be(true)
    expect(err.string).to be_empty
  end

  it "requires APP_HOST, naming it" do
    expect { described_class.verify!(complete.merge("APP_HOST" => " "), logger: logger, err: err) }
      .to raise_error(ProductionChecks::MissingConfiguration, /APP_HOST is required in production/)
  end

  it "no longer requires the encryption keys (they are generated)" do
    expect(described_class.required(complete)).not_to include(a_string_starting_with("ACTIVE_RECORD_ENCRYPTION"))
  end

  it "requires MAILER_FROM only when SMTP is configured" do
    expect { described_class.verify!(complete.except("MAILER_FROM"), logger: logger, err: err) }
      .to raise_error(ProductionChecks::MissingConfiguration, /MAILER_FROM is required in production/)
    expect(described_class.verify!(complete.except("SMTP_ADDRESS", "MAILER_FROM"), logger: logger, err: err)).to be(true)
  end

  it "names every missing variable at once" do
    env = complete.merge("APP_HOST" => " ", "MAILER_FROM" => "")
    expect { described_class.verify!(env, logger: logger, err: err) }
      .to raise_error(ProductionChecks::MissingConfiguration, /APP_HOST.*; MAILER_FROM/)
  end

  it "only warns when SMTP_ADDRESS is missing" do
    expect(described_class.verify!(complete.except("SMTP_ADDRESS"), logger: logger, err: err)).to be(true)
    expect(err.string).to include("[hideout] SMTP_ADDRESS is not set; email will not be delivered")
    expect(logger).to have_received(:warn).with(/SMTP_ADDRESS is not set/)
  end

  it "refuses open sign-up without SMTP" do
    env = complete.except("SMTP_ADDRESS").merge("HIDEOUT_OPEN_SIGNUP" => "true")
    expect { described_class.verify!(env, logger: logger, err: err) }
      .to raise_error(ProductionChecks::MissingConfiguration,
                      /HIDEOUT_OPEN_SIGNUP needs SMTP_ADDRESS so new accounts can verify their email/)
    expect(described_class.verify!(complete.merge("HIDEOUT_OPEN_SIGNUP" => "true"), logger: logger, err: err)).to be(true)
  end

  it "warns when HTTPS is off" do
    expect(described_class.verify!(complete.merge("HIDEOUT_FORCE_SSL" => "false"), logger: logger, err: err)).to be(true)
    expect(err.string).to include("[hideout] HTTPS is off: tokens and passwords travel in clear text")
  end

  context "when attachments live in S3" do
    let(:s3) do
      complete.merge("ACTIVE_STORAGE_SERVICE" => "s3", "S3_ENDPOINT" => "https://storage.example.com",
                     "S3_BUCKET" => "attachments", "S3_ACCESS_KEY_ID" => "k", "S3_SECRET_ACCESS_KEY" => "s")
    end

    it "passes when every S3 setting is present" do
      expect(described_class.verify!(s3, logger: logger, err: err)).to be(true)
    end

    %w[S3_BUCKET S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY].each do |name|
      it "names #{name} when it is missing" do
        expect { described_class.verify!(s3.except(name), logger: logger, err: err) }
          .to raise_error(ProductionChecks::MissingConfiguration, /#{name} is required in production/)
      end
    end

    it "requires a real region for AWS" do
      aws = s3.except("S3_ENDPOINT")
      expect { described_class.verify!(aws, logger: logger, err: err) }
        .to raise_error(ProductionChecks::MissingConfiguration, /S3_REGION must be set to your bucket's AWS region when S3_ENDPOINT is empty/)
      expect(described_class.verify!(aws.merge("S3_REGION" => "eu-central-1"), logger: logger, err: err)).to be(true)
    end

    it "refuses an endpoint with a path" do
      expect { described_class.verify!(s3.merge("S3_ENDPOINT" => "https://storage.example.com/bucket"), logger: logger, err: err) }
        .to raise_error(ProductionChecks::MissingConfiguration, /S3_ENDPOINT must be an http\(s\) URL with no path/)
    end

    it "accepts the deprecated R2 names and warns" do
      r2 = complete.merge("ACTIVE_STORAGE_SERVICE" => "r2", "R2_ENDPOINT" => "https://acct.r2.cloudflarestorage.com",
                          "R2_BUCKET" => "attachments", "R2_ACCESS_KEY_ID" => "k", "R2_SECRET_ACCESS_KEY" => "s")
      expect(described_class.verify!(r2, logger: logger, err: err)).to be(true)
      expect(err.string).to include("[hideout] R2_* settings are deprecated; rename them to S3_*")
    end
  end

  context "with offsite backups" do
    let(:backups) do
      complete.merge("BACKUP_BUCKET" => "backups", "S3_ENDPOINT" => "https://storage.example.com",
                     "BACKUP_S3_ACCESS_KEY_ID" => "bk", "BACKUP_S3_SECRET_ACCESS_KEY" => "bs")
    end

    it "passes with the backup key pair" do
      expect(described_class.verify!(backups, logger: logger, err: err)).to be(true)
    end

    %w[BACKUP_S3_ACCESS_KEY_ID BACKUP_S3_SECRET_ACCESS_KEY].each do |name|
      it "names #{name} when it is missing" do
        expect { described_class.verify!(backups.except(name), logger: logger, err: err) }
          .to raise_error(ProductionChecks::MissingConfiguration, /#{name} is required in production/)
      end
    end

    it "requires a real region for backups on AWS" do
      aws = backups.except("S3_ENDPOINT")
      expect { described_class.verify!(aws, logger: logger, err: err) }
        .to raise_error(ProductionChecks::MissingConfiguration,
                        /BACKUP_S3_REGION \(or S3_REGION\) must be set to the backup bucket's AWS region when BACKUP_S3_ENDPOINT and S3_ENDPOINT are empty/)
      expect(described_class.verify!(aws.merge("BACKUP_S3_REGION" => "eu-central-1"), logger: logger, err: err)).to be(true)
      expect(described_class.verify!(aws.merge("S3_REGION" => "eu-central-1"), logger: logger, err: err)).to be(true)
      expect(described_class.verify!(aws.merge("BACKUP_S3_ENDPOINT" => "https://backups.example.com"), logger: logger, err: err)).to be(true)
    end

    it "names the attachment region only once when both live on AWS" do
      aws = backups.except("S3_ENDPOINT").merge("ACTIVE_STORAGE_SERVICE" => "s3", "S3_BUCKET" => "a",
                                                 "S3_ACCESS_KEY_ID" => "k", "S3_SECRET_ACCESS_KEY" => "s")
      expect { described_class.verify!(aws, logger: logger, err: err) }
        .to raise_error(ProductionChecks::MissingConfiguration) { |error| expect(error.message.scan("AWS region").size).to eq(1) }
    end

    it "also checks the endpoint shape" do
      expect { described_class.verify!(backups.merge("S3_ENDPOINT" => "storage.example.com"), logger: logger, err: err) }
        .to raise_error(ProductionChecks::MissingConfiguration, /S3_ENDPOINT must be an http/)
    end
  end

  it "does not require S3 settings for the local service" do
    expect(described_class.verify!(complete.merge("ACTIVE_STORAGE_SERVICE" => "local"), logger: logger, err: err)).to be(true)
  end

  it "refuses an unknown storage service, naming the valid ones" do
    expect { described_class.verify!(complete.merge("ACTIVE_STORAGE_SERVICE" => "R2"), logger: logger, err: err) }
      .to raise_error(ProductionChecks::MissingConfiguration, /ACTIVE_STORAGE_SERVICE must be one of: local, s3 \(got R2\)/)
  end

  describe "S3_ENDPOINT shape" do
    let(:s3) do
      complete.merge("ACTIVE_STORAGE_SERVICE" => "s3", "S3_BUCKET" => "attachments",
                     "S3_ACCESS_KEY_ID" => "k", "S3_SECRET_ACCESS_KEY" => "s")
    end

    [ "acct.r2.cloudflarestorage.com", "https://acct.r2.cloudflarestorage.com/attachments",
      "ftp://acct.r2.cloudflarestorage.com", "https://acct.r2.cloudflarestorage.com/?x=1",
      "https://acct.r2.cloudflarestorage.com/#frag" ].each do |value|
      it "refuses #{value}" do
        expect { described_class.verify!(s3.merge("S3_ENDPOINT" => value), logger: logger, err: err) }
          .to raise_error(ProductionChecks::MissingConfiguration,
                          /S3_ENDPOINT must be an http\(s\) URL with no path, like https:\/\/<account>\.r2\.cloudflarestorage\.com \(got #{Regexp.escape(value)}\)/)
      end
    end

    [ "https://acct.r2.cloudflarestorage.com/", "http://localhost:9000" ].each do |value|
      it "accepts #{value}" do
        expect(described_class.verify!(s3.merge("S3_ENDPOINT" => value), logger: logger, err: err)).to be(true)
      end
    end
  end

  describe ".enabled?" do
    let(:production) { ActiveSupport::StringInquirer.new("production") }

    it "is on in production" do
      expect(described_class.enabled?({}, rails_env: production)).to be(true)
    end

    it "is off outside production" do
      expect(described_class.enabled?({}, rails_env: ActiveSupport::StringInquirer.new("test"))).to be(false)
    end

    it "is off during asset precompile (SECRET_KEY_BASE_DUMMY)" do
      expect(described_class.enabled?({ "SECRET_KEY_BASE_DUMMY" => "1" }, rails_env: production)).to be(false)
    end
  end

  it "refuses a setup code shorter than 8 letters or digits" do
    expect { described_class.verify!(complete.merge("HIDEOUT_SETUP_CODE" => "ab-12 34"), logger: logger, err: err) }
      .to raise_error(ProductionChecks::MissingConfiguration, /HIDEOUT_SETUP_CODE must have at least 8 letters or digits/)
    expect(described_class.verify!(complete.merge("HIDEOUT_SETUP_CODE" => "abcd-2345"), logger: logger, err: err)).to be(true)
  end

  it "counts only letters and digits in the setup code" do
    [ "!!!!!!!!", "abc!!!!!!" ].each do |code|
      expect { described_class.verify!(complete.merge("HIDEOUT_SETUP_CODE" => code), logger: logger, err: err) }
        .to raise_error(ProductionChecks::MissingConfiguration, /HIDEOUT_SETUP_CODE must have at least 8 letters or digits/)
    end
  end
end
