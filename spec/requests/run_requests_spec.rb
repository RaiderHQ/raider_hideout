require "rails_helper"

RSpec.describe "Run tests", type: :request do
  let(:org) { create(:organization) }
  let(:project) { create(:project, organization: org) }
  let(:token) { "ghp_#{'a' * 36}" }
  let(:users) do
    Membership::ROLES.index_with do |role|
      create(:user).tap { |u| create(:membership, organization: org, user: u, role: role) }
    end
  end
  let(:url) { "https://api.github.com/repos/acme/shop/actions/workflows/test_pipeline.yml/dispatches" }
  let(:any_request) { stub_request(:any, /api\.github\.com/) }

  before do
    CiAccess.create!(project: project, token: token, token_saved_at: Time.current, repository: "acme/shop",
                     workflow: "test_pipeline.yml", tag_input: "tags")
  end

  def act_as(role) = sign_in(users.fetch(role))

  def run_tests(ref: "main", tags: "") = post(project_run_requests_path(project), params: { run_request: { ref: ref, tags: tags } })

  it "forbids a viewer the form and the run, with no request" do
    any_request
    act_as("viewer")
    get new_project_run_request_path(project)
    expect(response).to have_http_status(:forbidden)
    run_tests
    expect(response).to have_http_status(:forbidden)
    expect(any_request).not_to have_been_requested
    expect(RunRequest.count).to eq(0)
  end

  it "404s another organization's project" do
    any_request
    sign_in(create(:user).tap { |u| create(:membership, user: u, role: "owner") })
    get new_project_run_request_path(project)
    expect(response).to have_http_status(:not_found)
    run_tests
    expect(response).to have_http_status(:not_found)
    expect(any_request).not_to have_been_requested
  end

  it "requires a CSRF token" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    act_as("member")
    any_request
    run_tests
    expect(any_request).not_to have_been_requested
    expect(RunRequest.count).to eq(0)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  it "shows the form prefilled with the default branch, recent branches, the tags field and the note" do
    create(:build, project: project, branch: "feature/a", default_branch: "trunk")
    create(:build, project: project, branch: "feature/b", default_branch: nil)
    act_as("member")
    get new_project_run_request_path(project)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Run tests", "Branch or tag", 'value="trunk"', '<option value="feature/b">', '<option value="feature/a">',
                                     "Tags (optional)", "Leave blank to run all tests. Example: @smoke", "Cancel",
                                     "Runs test_pipeline.yml on GitHub Actions in acme/shop. Results appear in Builds when the run uploads them.")
  end

  it "prefills main and hides the tags field without a tag input" do
    project.ci_access.update!(tag_input: nil)
    act_as("member")
    get new_project_run_request_path(project)
    expect(response.body).to include('value="main"')
    expect(response.body).not_to include("Tags (optional)")
  end

  it "redirects with the set-up copy when Run tests is not set up" do
    project.ci_access.update!(workflow: nil)
    act_as("member")
    get new_project_run_request_path(project)
    expect(response).to redirect_to(project_builds_path(project))
    expect(flash[:alert]).to eq("Ask an admin to set up Run tests in CI access.")
    act_as("admin")
    run_tests
    expect(flash[:alert]).to eq("Set up Run tests in CI access.")
  end

  it "answers an accepted run with a 303 to the builds list and the notice" do
    stub_request(:post, url).to_return(status: 204)
    act_as("member")
    run_tests(ref: "main", tags: "@smoke")
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(project_builds_path(project))
    expect(flash[:notice]).to eq("Tests requested on main. Results appear in Builds when the run uploads them.")
    expect(RunRequest.last).to have_attributes(tags: "@smoke", user: users.fetch("member"))
  end

  it "re-renders the form with 422, the alert and the typed values when GitHub refuses" do
    stub_request(:post, url).to_return(status: 422, body: { message: "No ref found for: nope" }.to_json)
    act_as("member")
    run_tests(ref: "nope", tags: "@smoke")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("GitHub refused the run: No ref found for: nope", 'value="nope"', 'value="@smoke"')
    expect(response.body).not_to include(token)
  end

  it "refuses a bad ref with 422 and no request" do
    any_request
    act_as("member")
    run_tests(ref: "a..b")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Enter a branch or tag name.")
    expect(any_request).not_to have_been_requested
  end

  it "ignores tags when no tag input is set" do
    project.ci_access.update!(tag_input: nil)
    stub = stub_request(:post, url).with { |req| !JSON.parse(req.body).key?("inputs") }.to_return(status: 204)
    act_as("member")
    run_tests(tags: "@smoke")
    expect(stub).to have_been_requested
    expect(RunRequest.last.tags).to be_nil
  end
end
