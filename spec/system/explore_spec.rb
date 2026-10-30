require "rails_helper"

RSpec.describe "Explore", type: :system do
  let(:organization) { create(:organization) }
  let(:owner) { create(:user).tap { create(:membership, organization: organization, user: _1, role: "owner") } }
  let(:viewer) { create(:user).tap { create(:membership, organization: organization, user: _1, role: "viewer") } }
  let(:project) { create(:project, organization: organization) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  before do
    search_result(create(:test_case, project: project, full_name: "Login works"), status: "failed", tags: [ "smoke" ])
    search_result(create(:test_case, project: project, full_name: "Cart totals"), status: "passed")
  end

  it "keeps the query box and the fields in sync, and shares a saved view" do
    sign_in_as(owner)
    visit project_explore_path(project)

    fill_in "q", with: "status:failed tag:smoke"
    click_on "Search"
    expect(page).to have_content("Login works")
    expect(page).to have_no_content("Cart totals")
    expect(find_field("status_failed")).to be_checked
    expect(find_field("Tags").value).to eq("smoke")

    check "status_passed"
    expect(page).to have_field("q", with: "status:passed,failed tag:smoke")
    expect(page).to have_current_path(/q=status%3Apassed%2Cfailed\+tag%3Asmoke/)

    fill_in "New view name", with: "Smoke checks"
    check "Share with the project"
    click_on "Save view"
    expect(page).to have_content("View saved.")

    Capybara.reset_sessions!
    sign_in_as(viewer)
    visit project_explore_path(project)
    within("[data-testid=saved-views]") { click_on "Smoke checks" }
    expect(page).to have_field("q", with: "status:passed,failed tag:smoke")
    expect(page).to have_no_button("Save", exact: true)
    expect(page).to have_no_button("Delete view")
  end
end
