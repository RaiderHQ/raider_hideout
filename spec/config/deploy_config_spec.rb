require "rails_helper"

RSpec.describe "Kamal example" do
  let(:env) do
    { "KAMAL_REGISTRY_IMAGE" => "raiderhq/hideout", "KAMAL_SERVER_IP" => "203.0.113.10",
      "KAMAL_REGISTRY_USERNAME" => "deploy", "APP_HOST" => "hideout.example.com" }
  end

  optional = %w[KAMAL_REGISTRY_SERVER MAILER_FROM SMTP_ADDRESS SMTP_PORT ACTIVE_STORAGE_SERVICE S3_ENDPOINT S3_REGION
                S3_BUCKET S3_FORCE_PATH_STYLE BACKUP_BUCKET BACKUP_S3_ENDPOINT BACKUP_S3_REGION HIDEOUT_FORCE_SSL
                HIDEOUT_ASSUME_SSL HIDEOUT_OPEN_SIGNUP HIDEOUT_SETUP_CODE RETENTION_ATTACHMENT_DAYS
                RETENTION_RESULT_DAYS DB_ADAPTER SENTRY_TRACES_SAMPLE_RATE]

  define_method(:render) do |overrides = {}|
    stub_const("ENV", ENV.to_h.except(*optional).merge(env).merge(overrides))
    YAML.safe_load(ERB.new(Rails.root.join("deploy/kamal/deploy.yml.example").read).result)
  end

  it "runs one web role with the storage volume and a Let's Encrypt certificate" do
    config = render
    expect(config["service"]).to eq("hideout")
    expect(config.dig("servers", "web")).to eq([ "203.0.113.10" ])
    expect(config["volumes"]).to eq([ "hideout_storage:/rails/storage" ])
    expect(config["proxy"]).to include("host" => "hideout.example.com", "app_port" => 3000, "ssl" => true)
    expect(config.dig("proxy", "healthcheck", "path")).to eq("/up")
    expect(config.dig("registry", "server")).to eq("ghcr.io")
  end

  it "needs only the server, image, registry user and host; everything else is optional" do
    clear = render.dig("env", "clear")
    expect(clear).to include("SOLID_QUEUE_IN_PUMA" => "1", "APP_HOST" => "hideout.example.com",
                             "ACTIVE_STORAGE_SERVICE" => "local", "SMTP_ADDRESS" => "")
  end

  it "passes every documented setting with the app's own defaults, never a blank that overrides one" do
    clear = render.dig("env", "clear")
    expect(clear).to include("HIDEOUT_FORCE_SSL" => "true", "HIDEOUT_ASSUME_SSL" => "false",
                             "HIDEOUT_OPEN_SIGNUP" => "false", "HIDEOUT_SETUP_CODE" => "",
                             "S3_FORCE_PATH_STYLE" => "", "BACKUP_S3_ENDPOINT" => "", "BACKUP_S3_REGION" => "",
                             "RETENTION_ATTACHMENT_DAYS" => "30", "RETENTION_RESULT_DAYS" => "90",
                             "DB_ADAPTER" => "", "SENTRY_TRACES_SAMPLE_RATE" => "0")
    expect(clear).not_to have_key("MAILER_FROM")
    expect(Retention::Config.from(clear)).to have_attributes(attachment_days: 30, result_days: 90)
    expect(StorageService.path_style?(clear)).to be(false)
    expect(StorageService.path_style?(clear.merge("ACTIVE_STORAGE_SERVICE" => "r2"))).to be(true)
  end

  it "passes what the deployer exports" do
    clear = render("HIDEOUT_OPEN_SIGNUP" => "true", "S3_FORCE_PATH_STYLE" => "true",
                   "MAILER_FROM" => "Hideout <ci@example.com>").dig("env", "clear")
    expect(clear).to include("HIDEOUT_OPEN_SIGNUP" => "true", "S3_FORCE_PATH_STYLE" => "true",
                             "MAILER_FROM" => "Hideout <ci@example.com>")
  end

  it "passes credentials only as secrets, and the secrets example lists each one" do
    secrets = render.dig("env", "secret")
    expect(secrets).to match_array(%w[SMTP_USERNAME SMTP_PASSWORD S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY
                                      BACKUP_S3_ACCESS_KEY_ID BACKUP_S3_SECRET_ACCESS_KEY SENTRY_DSN
                                      SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
                                      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
                                      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT])
    lines = Rails.root.join("deploy/kamal/secrets.example").readlines(chomp: true)
                 .reject { |line| line.strip.empty? || line.start_with?("#") }
    expect(lines).to all(match(/\A([A-Z0-9_]+)=\$\1\z/))
    expect(lines.map { |line| line.split("=").first }).to match_array(secrets + %w[KAMAL_REGISTRY_PASSWORD])
  end

  # Kamal sends an unset secret as an empty value. Secrets.load! treats that as unset,
  # but Rails does not for DATABASE_URL, so the Postgres line ships commented out.
  it "shows how to pass DATABASE_URL for Postgres without sending an empty one" do
    expect(Rails.root.join("deploy/kamal/deploy.yml.example").read).to match(/^\s+# - DATABASE_URL$/)
    expect(Rails.root.join("deploy/kamal/secrets.example").read).to match(/^# DATABASE_URL=\$DATABASE_URL$/)
  end

  it "fails loudly when a required value is missing" do
    stub_const("ENV", ENV.to_h.merge(env).except("KAMAL_SERVER_IP"))
    expect { ERB.new(Rails.root.join("deploy/kamal/deploy.yml.example").read).result }.to raise_error(KeyError, /KAMAL_SERVER_IP/)
  end
end
