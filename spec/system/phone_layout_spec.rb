require "rails_helper"

RSpec.describe "Phone layout", type: :system do
  let(:user) { create(:user) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  [ 360, 430 ].each do |width|
    it "nav fits a phone at #{width}px" do
      sign_in_as(user)

      at_phone_width(width) do
        visit root_path
        expect(page.evaluate_script("window.innerWidth")).to eq(width)
        expect_no_horizontal_scroll
        find("#account-menu summary").click
        expect_tap_targets("#account-menu summary, #account-menu a, #account-menu button")
        expect_no_horizontal_scroll
        click_on "Sign out"
        expect(page).to have_current_path(new_session_path)
      end
    end
  end

  describe "project list, project health and builds list" do
    let(:project) { create(:project, owner: user, name: "Phone project") }
    let(:long_branch) { "feature/a-very-long-branch-name-that-would-overflow-a-phone" }
    let(:long_message) { "Refactor the extremely verbose reporting pipeline so that every adapter shares one retry policy and stops overflowing" }

    before do
      30.times do |i|
        create(:build, project: project, branch: long_branch, commit_sha: "abc#{i}f1234",
                       commit_message: long_message, passed_count: 9, total_count: 10,
                       status: (i == 3 ? "failed" : "passed"), failed_count: (i == 3 ? 1 : 0),
                       duration_ms: 125_000)
      end
      sign_in_as(user)
    end

    [ 360, 430 ].each do |width|
      it "fit a phone at #{width}px" do
        at_phone_width(width) do
          [ projects_path, project_path(project), project_builds_path(project), project_builds_path(project, page: 2) ].each do |path|
            visit path
            expect(page).to have_css("main")
            expect_no_horizontal_scroll
            expect_tap_targets("main a, main button, main select, main summary")
          end

          visit project_builds_path(project)
          row_widths = page.evaluate_script(
            "Array.from(document.querySelectorAll('#builds > div')).map(function (el) { return el.getBoundingClientRect().width })"
          )
          expect(row_widths).not_to be_empty
          expect(row_widths.max).to be <= width
        end
      end
    end
  end

  it "keeps Tokens reachable in the account menu at desktop width" do
    sign_in_as(user)
    find("#account-menu summary").click
    within("#account-menu") { click_on "Tokens" }
    expect(page).to have_current_path(personal_tokens_path)
  end
end
