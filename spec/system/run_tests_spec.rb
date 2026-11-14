require "rails_helper"

RSpec.describe "Run tests", type: :system do
  include ActiveJob::TestHelper

  let(:organization) { create(:organization) }
  let(:project) { create(:project, organization: organization) }
  let(:token) { "ghp_#{'d' * 36}" }
  let(:url) { "https://api.github.com/repos/acme/shop-tests/actions/workflows/test_pipeline.yml/dispatches" }

  def user_with(role) = create(:user).tap { |u| create(:membership, organization: organization, user: u, role: role) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  def set_up(**attrs)
    CiAccess.create!({ project: project, token: token, token_saved_at: Time.current, repository: "acme/shop-tests",
                       workflow: "test_pipeline.yml", tag_input: "tags" }.merge(attrs))
  end

  [ 1280, 360 ].each do |width|
    context "at #{width} px" do
      def at_width(width, &) = width == 1280 ? yield : at_phone_width(width, &)

      it "shows each viewer the right control" do
        set_up(workflow: nil)
        sign_in_as(user_with("admin"))
        at_width(width) do
          visit project_builds_path(project)
          expect(page).to have_link("Set up Run tests in CI access.")
          expect(page).to have_no_css("#run_requests h2")
        end
        project.ci_access.update!(workflow: "test_pipeline.yml")
        sign_in_as(user_with("member"))
        at_width(width) do
          visit project_path(project)
          expect(page).to have_link("Run tests")
          expect_tap_targets("[data-testid=run-tests]") if width == 360
        end
        project.ci_access.update!(workflow: nil)
        visit project_builds_path(project)
        expect(page).to have_content("Ask an admin to set up Run tests in CI access.")
        sign_in_as(user_with("viewer"))
        visit project_builds_path(project)
        expect(page).to have_no_css("[data-testid=run-tests]")
      end

      it "starts a run and turns its line into the build link when the results arrive" do
        set_up
        create(:build, project: project, branch: "feature/login", default_branch: "main")
        stub_request(:post, url).to_return(status: 200, body: { workflow_run_id: 4242, html_url: "https://github.com/acme/shop-tests/actions/runs/4242" }.to_json)
        member = user_with("member")
        sign_in_as(member)
        at_width(width) do
          visit project_builds_path(project)
          click_on "Run tests"
          expect(page).to have_field("Branch or tag", with: "main")
          expect(page).to have_css("datalist#run-request-branches option[value='feature/login']", visible: :all)
          fill_in "Tags (optional)", with: "@smoke"
          click_on "Run tests"
          expect(page).to have_content("Tests requested on main. Results appear in Builds when the run uploads them.")
          line = find("[data-testid=run-request]")
          expect(line).to have_content("main · Tags: @smoke · requested by #{member.email_address} at")
          expect(line).to have_content("waiting for results")
          expect(line).to have_link("View on GitHub", href: "https://github.com/acme/shop-tests/actions/runs/4242")
          if width == 360
            expect_no_horizontal_scroll
            expect_tap_targets("[data-testid=run-request] a")
          end
          expect(page).to have_css("turbo-cable-stream-source[connected]", visible: :all)

          data = build_payload
          data["run"]["ci"] = { "provider" => "github_actions", "build_id" => "4242", "repository" => "Acme/Shop-Tests",
                                "attempt" => "1", "build_url" => "https://github.com/Acme/Shop-Tests/actions/runs/4242" }
          perform_enqueued_jobs { Ingest.call(project: project, payload: data.to_json, files: {}) }
          build = project.builds.find_by!(build_id: "4242")
          expect(page).to have_link("Build ##{build.id}", href: project_build_path(project, build))
          expect(page).to have_no_content("waiting for results")
        end
      end
    end
  end

  it "keeps the typed values and shows GitHub's answer when the run is refused" do
    set_up
    stub_request(:post, url).to_return(status: 422, body: { message: "No ref found for: nope" }.to_json)
    sign_in_as(user_with("member"))
    visit new_project_run_request_path(project)
    fill_in "Branch or tag", with: "nope"
    click_on "Run tests"
    expect(page).to have_content("GitHub refused the run: No ref found for: nope")
    expect(page).to have_field("Branch or tag", with: "nope")
    click_on "Cancel"
    expect(page).to have_current_path(project_builds_path(project))
    expect(find("[data-testid=run-request]")).to have_content("GitHub refused the run: No ref found for: nope")
  end
end
