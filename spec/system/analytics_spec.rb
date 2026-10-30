require "rails_helper"

RSpec.describe "Analytics", type: :system do
  let(:organization) { create(:organization) }
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
    build = analytics_build(project: project, at: 1.day.ago, passed_count: 1, failed_count: 1, duration_ms: 2_000, flaky_count: 1)
    login = create(:test_case, project: project, full_name: "Login works", file_path: "spec/login_spec.rb")
    cart = create(:test_case, project: project, full_name: "Cart totals", file_path: "spec/cart_spec.rb")
    spaced = create(:test_case, project: project, full_name: "Spaced out", file_path: "spec/b c_spec.rb")
    analytics_result(build: build, test_case: login, status: "failed")
    analytics_result(build: build, test_case: cart, status: "failed")
    analytics_result(build: build, test_case: spaced, status: "failed")
  end

  it "draws the charts and narrows the page to a spec file" do
    sign_in_as(viewer)
    visit project_path(project)
    click_on "Analytics"

    expect(page).to have_css("#failure-rate-chart canvas")
    expect(page).to have_css("#duration-chart canvas")
    expect(page).to have_css("#flaky-chart canvas")
    within("[data-testid=analytics-failing]") { expect(page).to have_content("Login works").and have_content("Cart totals") }

    within("[data-testid=analytics-files]") { click_on "spec/cart_spec.rb" }

    expect(page).to have_field("q", with: "file:spec/cart_spec.rb")
    within("[data-testid=analytics-failing]") do
      expect(page).to have_content("Cart totals")
      expect(page).to have_no_content("Login works")
    end
    expect(page).to have_content(AnalyticsHelper::BUILD_NOTE)
    expect(page).to have_css("#failure-rate-chart canvas")
  end

  it "narrows the page to a spec file whose path contains a space" do
    sign_in_as(viewer)
    visit project_analytics_path(project)

    within("[data-testid=analytics-files]") { click_on "spec/b c_spec.rb" }

    expect(page).to have_field("q", with: /file:.*spec\/b c_spec\.rb/)
    within("[data-testid=analytics-failing]") do
      expect(page).to have_content("Spaced out")
      expect(page).to have_no_content("Login works")
      expect(page).to have_no_content("Cart totals")
    end
  end
end
