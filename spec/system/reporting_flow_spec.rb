require "rails_helper"

RSpec.describe "Reporting flow", type: :system do
  before { open_signup! }

  it "takes a new user from sign-up to a failing test's history" do
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

    click_on "API tokens", match: :first
    fill_in "api_token[name]", with: "CI"
    click_on "Create token"
    expect(page).to have_content("only time it is shown")

    project = Project.find_by!(slug: "storefront")
    data = build_payload(results: [ build_result("status" => "failed", "full_name" => "Checkout pays",
      "failure" => { "message" => "card declined", "exception_class" => "RuntimeError", "backtrace" => [] }) ])
    run = Ingest.call(project: project, payload: data.to_json, files: {}).run

    visit project_run_path(project, run)
    expect(page).to have_content("card declined")
    click_on "History"
    expect(page).to have_content("Checkout pays")
  end
end
