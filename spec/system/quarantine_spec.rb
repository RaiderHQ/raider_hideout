require "rails_helper"

RSpec.describe "Quarantine", type: :system do
  let(:organization) { create(:organization) }
  let(:member) { create(:user).tap { create(:membership, organization: organization, user: _1, role: "member") } }
  let(:project) { create(:project, organization: organization) }
  let!(:flaky) do
    create(:test_case, project: project, full_name: "Checkout pays").tap do |kase|
      create(:test_case_verdict, test_case: kase, branch: "main", flaky: true, flaky_reason: "flips", flip_rate: 0.4)
    end
  end

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  it "quarantines from the flaky list, extends and releases on the test page, and keeps the trail" do
    sign_in_as(member)
    visit project_flaky_tests_path(project)
    click_on "Quarantine"

    fill_in "quarantine_reason", with: "Waits on the mail server"
    select "7 days", from: "quarantine_days"
    click_on "Quarantine"
    expect(page).to have_css("[data-testid=quarantine-banner]", text: "Waits on the mail server")
    expect(page).to have_css("[data-testid=quarantine-banner]", text: "Quarantined until #{Quarantine.sole.expires_at.strftime('%B %-d, %Y')}")

    visit project_quarantined_tests_path(project)
    expect(page).to have_css("[data-quarantine-row]", text: "Checkout pays")
    within("[data-quarantine-row]") { click_on "Checkout pays" }

    select "30 days", from: "extend_days"
    fill_in "extend_note", with: "still flaky"
    click_on "Extend"
    expect(page).to have_content("Quarantine extended until")

    fill_in "release_note", with: "fixed"
    click_on "Release"
    expect(page).to have_content("Quarantine released.")
    expect(page).to have_field("quarantine_reason")
    expect(page.all("[data-quarantine-event]").map { _1["data-quarantine-event"] }).to eq(%w[released extended quarantined])

    visit project_quarantined_tests_path(project)
    expect(page).to have_content("No tests are quarantined.")
    expect(page).to have_css("[data-quarantine-event]", count: 3)
  end

  it "quarantines and releases at phone width" do
    run = create(:run, project: project)
    create(:test_result, run: run, test_case: flaky, status: "failed", exception_class: "RuntimeError", failure_message: "boom")
    sign_in_as(member)

    at_phone_width(360) do
      visit project_build_path(project, run.build)
      click_on "History"
      expect(page).to have_field("quarantine_reason")
      expect_no_horizontal_scroll
      expect_tap_targets("#quarantine input:not([type=hidden]), #quarantine select")

      fill_in "quarantine_reason", with: "Waits on the mail server"
      click_on "Quarantine"
      expect(page).to have_css("[data-testid=quarantine-banner]", text: "Waits on the mail server")
      expect_no_horizontal_scroll
      expect_tap_targets("#quarantine input:not([type=hidden]), #quarantine select")

      click_on "Release"
      expect(page).to have_content("Quarantine released.")
      expect_no_horizontal_scroll
    end
  end
end
