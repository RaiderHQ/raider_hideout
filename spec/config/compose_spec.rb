require "rails_helper"

RSpec.describe "deploy/docker" do
  let(:compose) { YAML.safe_load(Rails.root.join("deploy/docker/compose.yml").read) }

  it "runs one web service from the published image with the storage volume" do
    web = compose.dig("services", "web")
    expect(web).to include("image" => "ghcr.io/raiderhq/hideout:${HIDEOUT_VERSION:-latest}", "env_file" => ".env", "restart" => "unless-stopped")
    expect(web["ports"]).to eq([ "127.0.0.1:${HIDEOUT_PORT:-3000}:3000" ])
    expect(web["volumes"]).to eq([ "hideout_storage:/rails/storage" ])
    expect(web.dig("environment", "SOLID_QUEUE_IN_PUMA")).to eq("1")
    expect(compose["volumes"]).to have_key("hideout_storage")
  end

  it "documents pinning a release in the install guide and the settings reference" do
    expect(Rails.root.join("docs/install/docker.md").read).to include("HIDEOUT_VERSION")
    expect(Rails.root.join("docs/install/configuration.md").read).to include("`HIDEOUT_VERSION`")
  end

  it "ships an .env.example with APP_HOST and every optional group commented out" do
    example = Rails.root.join("deploy/docker/.env.example").read
    expect(example).to match(/^APP_HOST=/)
    expect(example).to match(/^# HIDEOUT_VERSION=\d+\.\d+\.\d+$/)
    %w[SMTP_ADDRESS S3_BUCKET BACKUP_BUCKET SENTRY_DSN HIDEOUT_OPEN_SIGNUP HIDEOUT_SETUP_CODE].each do |name|
      expect(example).to match(/^# #{name}=/)
    end
  end
end
