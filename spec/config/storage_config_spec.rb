require "rails_helper"

RSpec.describe "config/storage.yml" do
  def services(env)
    stub_const("ENV", ENV.to_h.merge(env))
    YAML.load(ERB.new(Rails.root.join("config/storage.yml").read).result, aliases: true)
  end

  # Blobs uploaded under ACTIVE_STORAGE_SERVICE=r2 record "r2" as their service name.
  it "defines s3, and r2 with the same settings for older blobs" do
    config = services("S3_BUCKET" => "attachments", "S3_ENDPOINT" => "https://storage.example.com",
                      "S3_ACCESS_KEY_ID" => "k", "S3_SECRET_ACCESS_KEY" => "s")
    expect(config["s3"]).to include("service" => "S3", "bucket" => "attachments", "endpoint" => "https://storage.example.com",
                                    "region" => "auto", "force_path_style" => false)
    expect(config["r2"]).to eq(config["s3"])
  end

  it "omits the endpoint for AWS" do
    expect(services("S3_BUCKET" => "attachments", "S3_ENDPOINT" => nil, "R2_ENDPOINT" => nil)["s3"]).not_to have_key("endpoint")
  end
end
