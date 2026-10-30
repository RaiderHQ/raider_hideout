require "rails_helper"

RSpec.describe "First-run setup", type: :system do
  before do
    with_env("HIDEOUT_SETUP_CODE" => "ABCD-2345")
    Rails.configuration.x.first_run_redirect = true
    FirstRun.reset!
  end

  after do
    Rails.configuration.x.first_run_redirect = false
    FirstRun.reset!
  end

  it "goes from the setup link to the CI token" do
    visit "/setup?code=abcd-2345"
    fill_in "instance_setup[email_address]", with: "admin@example.com"
    fill_in "instance_setup[password]", with: "password123"
    fill_in "instance_setup[password_confirmation]", with: "password123"
    fill_in "instance_setup[organization_name]", with: "Acme QA"
    fill_in "instance_setup[project_name]", with: "Checkout"
    click_button "Create admin and project"
    expect(page).to have_text("Raider Hideout is ready")
    expect(page).to have_text(/RAIDER_TOKEN=rdr_/)
    click_link "Open Checkout"
    expect(page).to have_current_path(%r{/projects/})
  end
end
