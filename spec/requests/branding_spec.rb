require "rails_helper"

RSpec.describe "Branding", type: :request do
  it "names the product Raider Hideout on the sign-in page" do
    get new_session_path
    expect(response.body).to include("<title>Raider Hideout</title>", "Sign in to Raider Hideout")
  end

  # The manifest has no route yet (the PWA routes are off), so check the template.
  it "names the app in the PWA manifest template" do
    manifest = Rails.root.join("app/views/pwa/manifest.json.erb").read
    expect(manifest).to include('"name": "Raider Hideout"', '"short_name": "Hideout"')
    expect(manifest).not_to include("RaiderSaas")
  end

  it "sends mail as Raider Hideout by default" do
    expect(ApplicationMailer.default[:from]).to eq(ENV.fetch("MAILER_FROM", "Raider Hideout <no-reply@localhost>"))
  end

  it "points the static error pages back to Raider Hideout" do
    %w[404 422 500].each do |code|
      expect(Rails.root.join("public/#{code}.html").read).to include("Back to Raider Hideout")
    end
  end
end
