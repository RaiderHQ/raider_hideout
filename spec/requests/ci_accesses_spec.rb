require "rails_helper"

RSpec.describe "CI access", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:org) { create(:organization) }
  let(:project) { create(:project, organization: org) }
  let(:token) { "ghp_#{'b' * 36}" }
  let(:users) do
    Membership::ROLES.index_with do |role|
      create(:user).tap { |u| create(:membership, organization: org, user: u, role: role) }
    end
  end

  def act_as(role) = sign_in(users.fetch(role))

  def save_token(value = token) = patch(project_ci_access_path(project), params: { ci_access: { token: value } })

  %w[viewer member].each do |role|
    it "forbids a #{role} everything" do
      act_as(role)
      get project_ci_access_path(project)
      expect(response).to have_http_status(:forbidden)
      save_token
      expect(response).to have_http_status(:forbidden)
      post test_project_ci_access_path(project)
      expect(response).to have_http_status(:forbidden)
      delete project_ci_access_path(project)
      expect(response).to have_http_status(:forbidden)
      expect(CiAccess.count).to eq(0)
    end
  end

  %w[admin owner].each do |role|
    it "lets an #{role} view the empty page" do
      act_as(role)
      get project_ci_access_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("CI access", "GitHub token",
                                       "A fine-grained token for this repository with Actions: Read and write and Metadata: Read. " \
                                       "Hideout uses it to re-run failed jobs and to start the test workflow.")
      expect(response.body).not_to include("Remove token")
    end
  end

  it "saves the token encrypted and never renders it" do
    act_as("admin")
    travel_to Time.zone.parse("2026-11-02 12:00:00") do
      save_token
    end
    expect(response).to redirect_to(project_ci_access_path(project))
    expect(response.body).not_to include(token)
    access = project.reload.ci_access
    expect(access.token).to eq(token)
    expect(CiAccess.connection.select_value("SELECT token FROM ci_accesses")).not_to include(token)
    follow_redirect!
    expect(response.body).to include("Token saved on November 2, 2026.", "Replace token", "Remove token", "Test connection")
    expect(response.body).not_to include(token)
  end

  it "replaces a token and clears the last check" do
    act_as("admin")
    save_token
    project.ci_access.update!(checked_at: Time.current, check_ok: true, check_message: "ok")
    save_token("ghp_#{'c' * 36}")
    expect(project.reload.ci_access).to have_attributes(token: "ghp_#{'c' * 36}", checked_at: nil, check_ok: nil, check_message: nil)
    expect(CiAccess.count).to eq(1)
  end

  it "rejects a bad format with the copy and without echoing the value" do
    act_as("admin")
    save_token("not-a-token-secret")
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("That doesn&#39;t look like a GitHub token.")
    expect(response.body).not_to include("not-a-token-secret")
    expect(CiAccess.count).to eq(0)
  end

  it "removes the token" do
    act_as("admin")
    save_token
    delete project_ci_access_path(project)
    expect(response).to redirect_to(project_ci_access_path(project))
    expect(CiAccess.count).to eq(0)
  end

  it "does not log the token" do
    act_as("admin")
    io = StringIO.new
    loggers = [ Rails, ActionController::Base, ActiveRecord::Base ].to_h { |k| [ k, k.logger ] }
    logger = ActiveSupport::Logger.new(io)
    Rails.logger = logger
    ActionController::Base.logger = logger
    ActiveRecord::Base.logger = logger
    begin
      save_token
    ensure
      Rails.logger = loggers[Rails]
      ActionController::Base.logger = loggers[ActionController::Base]
      ActiveRecord::Base.logger = loggers[ActiveRecord::Base]
    end
    expect(io.string).to include("Parameters", "[FILTERED]")
    expect(io.string).not_to include(token)
  end

  it "keeps the old saved date and check when a replacement is rejected" do
    act_as("admin")
    travel_to(Time.zone.parse("2026-11-02 12:00:00")) { save_token }
    project.ci_access.update!(checked_at: Time.current, check_ok: true, check_message: "Earlier check passed.")
    travel_to(Time.zone.parse("2026-11-09 12:00:00")) { save_token("nope") }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Token saved on November 2, 2026.", "Earlier check passed.")
    expect(project.ci_access.reload.token).to eq(token)
  end

  it "does not touch another project's token" do
    other = create(:project, organization: org)
    CiAccess.create!(project: other, token: token, token_saved_at: Time.current)
    act_as("admin")
    delete project_ci_access_path(project)
    expect(CiAccess.count).to eq(1)
  end

  describe "Test connection" do
    before { act_as("admin") }

    it "asks for a token first" do
      post test_project_ci_access_path(project)
      expect(flash[:alert]).to eq("Add a GitHub token in CI access first.")
    end

    it "says to wait when no GitHub build exists" do
      save_token
      create(:build, project: project, provider: "other", ci_run_key: "github_actions:o/r:1")
      create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:../r:1")
      create(:build, project: project, provider: "github_actions", ci_run_key: nil)
      post test_project_ci_access_path(project)
      expect(response).to redirect_to(project_ci_access_path(project))
      expect(flash[:notice]).to eq("Saved. Test it after the first GitHub Actions build arrives.")
      expect(project.ci_access.reload.checked_at).to be_nil
    end

    it "calls the latest GitHub build's repository and stores the result" do
      save_token
      create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:old/repo:1")
      create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:octo/hello:22")
      stub = stub_request(:get, "https://api.github.com/repos/octo/hello").to_return(status: 200, body: "{}")
      travel_to(Time.zone.parse("2026-11-02 12:00:00")) { post test_project_ci_access_path(project) }
      expect(stub).to have_been_requested.once
      message = "GitHub accepted the token and can see octo/hello. Re-runs and Run tests also need Actions: Read and write."
      expect(flash[:notice]).to eq(message)
      expect(project.ci_access.reload).to have_attributes(check_ok: true, check_message: message,
                                                          checked_at: Time.zone.parse("2026-11-02 12:00:00"))
      follow_redirect!
      expect(response.body).to include(message)
    end

    {
      401 => "GitHub rejected the token. Replace it in CI access.",
      403 => "GitHub refused: the token needs Actions: Read and write for this repository.",
      404 => "GitHub can't find this repository, or the token can't see it.",
      429 => "GitHub is busy. Try again in a minute.",
      502 => "GitHub is busy. Try again in a minute."
    }.each do |status, copy|
      it "explains a #{status}" do
        save_token
        create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:octo/hello:22")
        stub_request(:get, "https://api.github.com/repos/octo/hello").to_return(status: status, body: { message: "x #{token}" }.to_json)
        post test_project_ci_access_path(project)
        expect(flash[:alert]).to eq(copy)
        expect(project.ci_access.reload).to have_attributes(check_ok: false, check_message: copy)
        expect(response.body).not_to include(token)
      end
    end

    it "reports a network failure and a redirect without following it" do
      save_token
      create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:octo/hello:22")
      stub_request(:get, "https://api.github.com/repos/octo/hello").to_timeout
      post test_project_ci_access_path(project)
      expect(flash[:alert]).to eq("Couldn't reach GitHub.")

      stub_request(:get, "https://api.github.com/repos/octo/hello").to_return(status: 301, headers: { "Location" => "https://evil.example/" })
      evil = stub_request(:get, "https://evil.example/")
      post test_project_ci_access_path(project)
      expect(project.ci_access.reload.check_ok).to be(false)
      expect(evil).not_to have_been_requested
    end
  end

  describe "Run tests settings" do
    def save_settings(**values) = patch(settings_project_ci_access_path(project), params: { ci_access: values })

    %w[viewer member].each do |role|
      it "forbids a #{role}" do
        CiAccess.create!(project: project, token: token, token_saved_at: Time.current)
        act_as(role)
        save_settings(repository: "a/b")
        expect(response).to have_http_status(:forbidden)
        expect(project.ci_access.reload.repository).to be_nil
      end
    end

    it "asks for a token first" do
      act_as("admin")
      save_settings(repository: "a/b")
      expect(response).to redirect_to(project_ci_access_path(project))
      expect(flash[:alert]).to eq("Add a GitHub token in CI access first.")
      expect(CiAccess.count).to eq(0)
    end

    it "saves the settings without a token param and keeps the token" do
      act_as("admin")
      save_token
      saved_at = project.ci_access.token_saved_at
      save_settings(repository: "acme/shop-tests", workflow: "test_pipeline.yml", tag_input: "tags", token: "ghp_#{'z' * 36}")
      expect(response).to redirect_to(project_ci_access_path(project))
      expect(flash[:notice]).to eq("Settings saved.")
      expect(project.ci_access.reload).to have_attributes(token: token, token_saved_at: saved_at, repository: "acme/shop-tests",
                                                          workflow: "test_pipeline.yml", tag_input: "tags")
      follow_redirect!
      expect(response.body).not_to include(token)
    end

    it "keeps the settings when only the token is replaced" do
      act_as("admin")
      save_token
      save_settings(repository: "acme/shop", workflow: "x.yml", tag_input: "tags")
      save_token("ghp_#{'c' * 36}")
      expect(project.ci_access.reload).to have_attributes(repository: "acme/shop", workflow: "x.yml", tag_input: "tags")
    end

    it "re-renders the form with each format error and keeps the typed values" do
      act_as("admin")
      save_token
      save_settings(repository: "a/b/c", workflow: "x.json", tag_input: "1tags")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Enter the repository as owner/name.", "Enter a workflow file name ending in .yml or .yaml.",
                                       "Use letters, numbers, - and _ for the input name.", 'value="a/b/c"', 'value="x.json"')
      expect(response.body).not_to include(token)
      expect(project.ci_access.reload.repository).to be_nil
    end

    it "prefills the repository from the latest GitHub Actions build until one is saved" do
      act_as("admin")
      save_token
      create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:Acme/Shop:2")
      get project_ci_access_path(project)
      expect(response.body).to include("Run tests", "Repository", "Workflow file", "Tag input (optional)", 'value="Acme/Shop"',
                                       "The GitHub repository, as owner/name. For example: acme/shop-tests.",
                                       "The file name in .github/workflows, for example test_pipeline.yml. It needs a workflow_dispatch trigger.",
                                       "The name of a workflow_dispatch input that takes tags, for example tags. Leave it blank to always run all tests.",
                                       "Save settings")
      save_settings(repository: "acme/other", workflow: "", tag_input: "")
      get project_ci_access_path(project)
      expect(response.body).to include('value="acme/other"')
    end

    describe "Test connection with settings" do
      let(:ok_copy) { "GitHub accepted the token and can see acme/shop. Re-runs and Run tests also need Actions: Read and write." }

      before do
        act_as("admin")
        save_token
        create(:build, project: project, provider: "github_actions", ci_run_key: "github_actions:octo/hello:22")
      end

      it "uses the saved repository before the detected one" do
        save_settings(repository: "acme/shop")
        stub = stub_request(:get, "https://api.github.com/repos/acme/shop").to_return(status: 200, body: "{}")
        post test_project_ci_access_path(project)
        expect(stub).to have_been_requested.once
        expect(flash[:notice]).to eq(ok_copy)
      end

      it "tests a saved repository before any build arrives" do
        project.builds.delete_all
        save_settings(repository: "acme/shop")
        stub_request(:get, "https://api.github.com/repos/acme/shop").to_return(status: 200, body: "{}")
        post test_project_ci_access_path(project)
        expect(flash[:notice]).to eq(ok_copy)
      end

      it "says when the workflow is found" do
        save_settings(repository: "acme/shop", workflow: "test_pipeline.yml")
        stub_request(:get, "https://api.github.com/repos/acme/shop").to_return(status: 200, body: "{}")
        stub_request(:get, "https://api.github.com/repos/acme/shop/actions/workflows/test_pipeline.yml").to_return(status: 200, body: "{}")
        post test_project_ci_access_path(project)
        expect(flash[:notice]).to eq("#{ok_copy} Found test_pipeline.yml.")
        expect(project.ci_access.reload.check_message).to eq("#{ok_copy} Found test_pipeline.yml.")
      end

      it "says when the workflow is missing" do
        save_settings(repository: "acme/shop", workflow: "test_pipeline.yml")
        stub_request(:get, "https://api.github.com/repos/acme/shop").to_return(status: 200, body: "{}")
        stub_request(:get, "https://api.github.com/repos/acme/shop/actions/workflows/test_pipeline.yml").to_return(status: 404, body: "{}")
        post test_project_ci_access_path(project)
        expect(flash[:notice]).to eq("#{ok_copy} GitHub can't find test_pipeline.yml in acme/shop.")
      end

      it "does not ask for the workflow when the repository check fails" do
        save_settings(repository: "acme/shop", workflow: "test_pipeline.yml")
        stub_request(:get, "https://api.github.com/repos/acme/shop").to_return(status: 401, body: "{}")
        workflow = stub_request(:get, %r{/actions/workflows/})
        post test_project_ci_access_path(project)
        expect(flash[:alert]).to eq("GitHub rejected the token. Replace it in CI access.")
        expect(workflow).not_to have_been_requested
      end
    end
  end
end
