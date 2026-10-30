require "rails_helper"

RSpec.describe "Quality gate", type: :system do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user).tap { create(:membership, organization: organization, user: _1, role: "admin") } }
  let(:project) { create(:project, organization: organization) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  it "lets an admin set the rules, evaluates a build with them and shows the verdict" do
    sign_in_as(admin)
    visit project_path(project)
    click_on "Gate"
    fill_in "Minimum pass rate (%)", with: "98"
    check "No new failures vs the default branch"
    click_on "Save gate rules"
    expect(page).to have_content("Gate rules saved. They apply to builds evaluated from now on.")

    build = create(:build, project: project, branch: "main", commit_message: "Gate me")
    run = create(:run, project: project, build: build, total_count: 4, passed_count: 3, failed_count: 1)
    FlakinessJob.perform_now(run.id)

    visit project_build_path(project, build)
    expect(page).to have_css("[data-testid=gate-badge]", text: /gate failed/i)
    within("[data-testid=gate-panel]") do
      expect(page).to have_css("[data-gate-rule=pass_rate][data-gate-outcome=failed]", text: "75% < 98%")
      expect(page).to have_css("[data-gate-rule=new_failures][data-gate-outcome=skipped]", text: "no baseline build on main")
    end

    visit project_builds_path(project)
    expect(page).to have_css("[data-testid=gate-cell][title='Gate failed']", text: "✗")
  end
end
