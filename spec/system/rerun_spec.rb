require "rails_helper"

RSpec.describe "Re-run failed", type: :system do
  let(:organization) { create(:organization) }
  let(:project) { create(:project, organization: organization) }
  let(:token) { "ghp_#{'e' * 36}" }
  let(:url) { "https://api.github.com/repos/octo/hello/actions/runs/123/rerun-failed-jobs" }
  let!(:build_record) do
    create(:build, project: project, provider: "github_actions", status: "failed",
                   ci_run_key: "github_actions:octo/hello:123", latest_attempt: 1)
  end
  let!(:result) { create(:test_result, run: create(:run, project: project, build: build_record), status: "failed") }

  def user_with(role) = create(:user).tap { create(:membership, organization: organization, user: _1, role: role) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  def add_token = CiAccess.create!(project: project, token: token, token_saved_at: Time.current)

  [ [ "desktop", nil ], [ "phone", 360 ] ].each do |label, width|
    context "at #{label} width" do
      def run_at(width, &block) = width ? at_phone_width(width, &block) : block.call

      it "shows the button to a member, which requests, flashes and shows the pending line" do
        add_token
        stub = stub_request(:post, url).to_return(status: 201, body: "")
        member = user_with("member")
        sign_in_as(member)
        run_at(width) do
          visit project_build_path(project, build_record)
          expect(page).to have_button("Re-run failed", minimum: 2)
          if width
            expect_tap_targets("form.button_to button")
            expect_no_horizontal_scroll
          end
          first(:button, "Re-run failed", match: :first).click
          expect(page).to have_content("Re-run requested. The result arrives as attempt 2.")
          expect(page).to have_content("Re-run requested by #{member.email_address} at")
          expect(page).to have_no_button("Re-run failed")
          expect(page).to have_content("waiting for GitHub").or have_content("GitHub accepted")
          expect_no_horizontal_scroll if width
        end
        expect(stub).to have_been_requested.once
      end

      it "returns to the card anchor from a card button" do
        add_token
        stub_request(:post, url).to_return(status: 201, body: "")
        sign_in_as(user_with("member"))
        run_at(width) do
          visit project_build_path(project, build_record)
          within("##{ActionView::RecordIdentifier.dom_id(result)}") { click_button "Re-run failed" }
          expect(page).to have_content("Re-run requested.")
          expect(page.evaluate_script("location.hash")).to eq("#test_result_#{result.id}")
        end
      end
    end
  end

  it "hides the button from a viewer" do
    add_token
    sign_in_as(user_with("viewer"))
    visit project_build_path(project, build_record)
    expect(page).to have_content(build_record.status.capitalize).or have_css("h1")
    expect(page).to have_no_button("Re-run failed")
  end

  it "hides the button on a passed build" do
    add_token
    build_record.update!(status: "passed")
    sign_in_as(user_with("member"))
    visit project_build_path(project, build_record)
    expect(page).to have_no_button("Re-run failed")
  end

  it "hides the button without a ci_run_key" do
    add_token
    build_record.update!(ci_run_key: nil)
    sign_in_as(user_with("member"))
    visit project_build_path(project, build_record)
    expect(page).to have_no_button("Re-run failed")
    expect(page).to have_no_content("GitHub token")
  end

  it "tells an admin without a token to add one, with a link" do
    sign_in_as(user_with("admin"))
    visit project_build_path(project, build_record)
    expect(page).to have_no_button("Re-run failed")
    click_on "Add a GitHub token in CI access first."
    expect(page).to have_current_path(project_ci_access_path(project))
  end

  it "tells a member without a token to ask an admin, as text" do
    sign_in_as(user_with("member"))
    visit project_build_path(project, build_record)
    expect(page).to have_content("Ask an admin to add a GitHub token in CI access.")
    expect(page).to have_no_link("Add a GitHub token in CI access first.")
    expect(page).to have_no_button("Re-run failed")
  end

  it "shows a viewer nothing without a token" do
    sign_in_as(user_with("viewer"))
    visit project_build_path(project, build_record)
    expect(page).to have_no_content("GitHub token")
  end

  it "lists the starter's name in the record" do
    add_token
    starter = user_with("member")
    build_record.reruns.create!(user: starter, attempt_before: 0, status: "accepted", http_status: 201)
    sign_in_as(user_with("viewer"))
    visit project_build_path(project, build_record)
    expect(page).to have_content("Re-run requested by #{starter.email_address}")
  end
end
