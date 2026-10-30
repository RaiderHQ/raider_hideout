require "rails_helper"

RSpec.describe "Live build", type: :system do
  include ActiveJob::TestHelper

  before { open_signup! }

  def ingest_shard(project, index)
    data = build_payload
    data["run"]["ci"]["build_key"] = "github_actions:RaiderHQ/demo:999:1"
    data["run"]["ci"]["job"] = "rspec"
    data["run"]["shard"] = { "index" => index, "total" => 2, "label" => "rspec##{index}" }
    perform_enqueued_jobs { Ingest.call(project: project, payload: data.to_json, files: {}) }
  end

  it "updates the builds list as each shard of a build arrives, without a reload" do
    visit new_registration_path
    fill_in "Email", with: "qa@example.com"
    fill_in "Password (8+ characters)", with: "password123"
    fill_in "Confirm password", with: "password123"
    click_on "Sign up"

    expect(page).to have_content("Check your inbox")
    user = User.find_by!(email_address: "qa@example.com")
    visit verify_email_confirm_path(token: user.generate_token_for(:email_verification))
    expect(page).to have_content("Email verified")

    click_on "New project"
    fill_in "Project name", with: "Storefront"
    click_on "Create project"
    expect(page).to have_content("No builds yet")

    project = Project.find_by!(slug: "storefront")
    visit project_builds_path(project)
    expect(page).to have_content("No builds yet")
    expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)
    page.execute_script("window.liveBuildMarker = true")

    ingest_shard(project, 1)
    expect(page).to have_content("1/2 shards")

    ingest_shard(project, 2)
    expect(page).to have_content("2/2 shards")
    expect(page).to have_no_content("1/2 shards")
    expect(project.builds.count).to eq(1)
    expect(page.evaluate_script("window.liveBuildMarker")).to be(true)
  end
end
