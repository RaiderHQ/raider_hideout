require "rails_helper"

RSpec.describe "CI access", type: :system do
  let(:organization) { create(:organization) }
  let(:admin) { create(:user).tap { create(:membership, organization: organization, user: _1, role: "admin") } }
  let(:member) { create(:user).tap { create(:membership, organization: organization, user: _1, role: "member") } }
  let(:project) { create(:project, organization: organization) }
  let(:token) { "ghp_#{'d' * 36}" }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  it "lets an admin save, test and remove a token" do
    create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:octo/hello:5")
    stub_request(:get, "https://api.github.com/repos/octo/hello").to_return(status: 200, body: "{}")
    sign_in_as(admin)
    visit project_path(project)
    click_on "CI access"
    fill_in "GitHub token", with: token
    click_on "Save token"
    expect(page).to have_content("Token saved on")
    expect(page).not_to have_content(token)
    expect(page).to have_no_css("input[value='#{token}']")
    click_on "Test connection"
    expect(page).to have_content("GitHub accepted the token and can see octo/hello.")
    accept_confirm { click_on "Remove token" }
    expect(page).to have_button("Save token")
  end

  it "hides the link from members" do
    sign_in_as(member)
    visit project_path(project)
    expect(page).to have_no_link("CI access")
  end
end
