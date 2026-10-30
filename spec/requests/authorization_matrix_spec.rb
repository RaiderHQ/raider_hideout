require "rails_helper"

RSpec.describe "Authorization matrix", type: :request do
  let(:org) { create(:organization) }
  let(:project) { create(:project, organization: org) }
  let(:users) do
    Membership::ROLES.index_with do |role|
      create(:user).tap { |u| create(:membership, organization: org, user: u, role: role) }
    end
  end
  let(:outsider) { create(:user) }
  let(:channel_params) { { notification_channel: { name: "Mail", kind: "email", recipients: "a@x.io" } } }

  def act_as(role)
    sign_in(users.fetch(role))
  end

  describe "API tokens" do
    it "forbids viewers on create and destroy" do
      token, = ApiToken.issue!(project: project, name: "CI")
      act_as("viewer")
      post project_api_tokens_path(project), params: { api_token: { name: "x" } }
      expect(response).to have_http_status(:forbidden)
      delete project_api_token_path(project, token)
      expect(response).to have_http_status(:forbidden)
      expect(project.api_tokens.count).to eq(1)
    end

    %w[member admin owner].each do |role|
      it "lets #{role} create and revoke" do
        act_as(role)
        post project_api_tokens_path(project), params: { api_token: { name: "x" } }
        expect(response).to have_http_status(:ok)
        delete project_api_token_path(project, project.api_tokens.first)
        expect(response).to redirect_to(project_api_tokens_path(project))
      end
    end

    it "ignores extra params on create" do
      act_as("member")
      post project_api_tokens_path(project), params: { api_token: { name: "x", token_digest: "abc", project_id: 0 } }
      expect(response).to have_http_status(:ok)
      token = project.api_tokens.first
      expect(token.token_digest).not_to eq("abc")
      expect(token.project).to eq(project)
    end
  end

  describe "notification channels" do
    let!(:channel) { create(:notification_channel, :email, project: project) }

    it "forbids viewers on every write action" do
      act_as("viewer")
      get new_project_notification_channel_path(project)
      expect(response).to have_http_status(:forbidden)
      post project_notification_channels_path(project), params: channel_params
      expect(response).to have_http_status(:forbidden)
      get edit_project_notification_channel_path(project, channel)
      expect(response).to have_http_status(:forbidden)
      patch project_notification_channel_path(project, channel), params: { notification_channel: { name: "Z" } }
      expect(response).to have_http_status(:forbidden)
      post test_project_notification_channel_path(project, channel)
      expect(response).to have_http_status(:forbidden)
      delete project_notification_channel_path(project, channel)
      expect(response).to have_http_status(:forbidden)
      expect(channel.reload.name).not_to eq("Z")
    end

    it "lets viewers read the index" do
      act_as("viewer")
      get project_notification_channels_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Send test")
    end

    it "lets members manage channels" do
      act_as("member")
      get new_project_notification_channel_path(project)
      expect(response).to have_http_status(:ok)
      post project_notification_channels_path(project), params: channel_params
      expect(response).to redirect_to(project_notification_channels_path(project))
      get edit_project_notification_channel_path(project, channel)
      expect(response).to have_http_status(:ok)
      delete project_notification_channel_path(project, channel)
      expect(response).to redirect_to(project_notification_channels_path(project))
    end
  end

  describe "project destroy" do
    %w[viewer member].each do |role|
      it "forbids #{role}" do
        act_as(role)
        delete project_path(project)
        expect(response).to have_http_status(:forbidden)
        expect(Project.exists?(project.id)).to be(true)
      end
    end

    %w[admin owner].each do |role|
      it "lets #{role} delete a project with all its dependents" do
        build = create(:build, project: project)
        run = create(:run, project: project, build: build)
        test_case = create(:test_case, project: project)
        verdict = create(:test_case_verdict, test_case: test_case, branch: "main", flaky: true, flaky_since_build: build)
        result = create(:test_result, run: run, test_case: test_case)
        channel = create(:notification_channel, :email, project: project)
        delivery = create(:notification_delivery, notification_channel: channel, build: build)
        token, = ApiToken.issue!(project: project, name: "CI")
        act_as(role)
        delete project_path(project)
        expect(response).to redirect_to(projects_path)
        [ project, build, run, test_case, verdict, result, channel, delivery, token ].each do |record|
          expect(record.class.exists?(record.id)).to be(false), "#{record.class} survived"
        end
      end
    end

    it "shows the delete button only to admins and owners" do
      act_as("member")
      get project_path(project)
      expect(response.body).not_to include("Delete project")
      sign_in(users.fetch("admin"))
      get project_path(project)
      expect(response.body).to include("Delete project")
    end
  end

  describe "project create" do
    it "forbids viewers in the chosen organization" do
      act_as("viewer")
      expect { post projects_path, params: { project: { name: "Shop", organization_id: org.id } } }.not_to change(Project, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it "lets members create into the organization" do
      act_as("member")
      post projects_path, params: { project: { name: "Shop", organization_id: org.id } }
      expect(response).to redirect_to(project_path("shop"))
      expect(org.projects.pluck(:name)).to eq([ "Shop" ])
    end

    it "404s for an organization the user is not in" do
      sign_in(outsider)
      post projects_path, params: { project: { name: "Shop", organization_id: org.id } }
      expect(response).to have_http_status(:not_found)
    end

    it "ignores a submitted personal flag and creates no organization" do
      act_as("member")
      org
      expect { post projects_path, params: { project: { name: "Shop", organization_id: org.id, personal: true } } }
        .not_to change(Organization, :count)
      expect(Project.find_by!(name: "Shop").organization).to eq(org)
    end

    it "defaults to the personal organization" do
      sign_in(outsider)
      post projects_path, params: { project: { name: "Mine" } }
      expect(outsider.personal_organization.projects.pluck(:name)).to eq([ "Mine" ])
    end

    it "lists only organizations with member+ role on the new form" do
      viewer_only = create(:organization, name: "ViewerOnly")
      create(:membership, organization: viewer_only, user: users.fetch("member"), role: "viewer")
      act_as("member")
      get new_project_path
      select_html = response.body[/<select.*?<\/select>/m]
      expect(select_html).to include(org.name)
      expect(select_html).not_to include("ViewerOnly")
    end
  end

  describe "reads" do
    Membership::ROLES.each do |role|
      it "lets #{role} read" do
        build = create(:build, project: project)
        run = create(:run, project: project, build: build)
        test_case = create(:test_case, project: project)
        act_as(role)
        [ project_path(project), project_builds_path(project), project_build_path(project, build),
          project_runs_path(project), project_run_path(project, run), project_flaky_tests_path(project),
          project_test_case_path(project, test_case), project_api_tokens_path(project) ].each do |path|
          get path
          expect(response).to have_http_status(:ok), "#{role} GET #{path} -> #{response.status}"
        end
      end
    end
  end

  describe "non-members" do
    it "get 404 on every project route" do
      channel = create(:notification_channel, :email, project: project)
      build = create(:build, project: project)
      run = create(:run, project: project, build: build)
      test_case = create(:test_case, project: project)
      token, = ApiToken.issue!(project: project, name: "CI")
      sign_in(outsider)
      get project_path(project)
      expect(response).to have_http_status(:not_found)
      get project_builds_path(project)
      expect(response).to have_http_status(:not_found)
      [ [ :get, project_path(project) ], [ :get, project_api_tokens_path(project) ],
        [ :post, project_api_tokens_path(project) ], [ :get, project_notification_channels_path(project) ],
        [ :get, new_project_notification_channel_path(project) ],
        [ :post, project_notification_channels_path(project) ], [ :get, project_flaky_tests_path(project) ],
        [ :delete, project_path(project) ], [ :get, project_builds_path(project) ],
        [ :get, project_build_path(project, build) ], [ :get, project_runs_path(project) ],
        [ :get, project_run_path(project, run) ], [ :get, project_test_case_path(project, test_case) ],
        [ :get, edit_project_notification_channel_path(project, channel) ],
        [ :patch, project_notification_channel_path(project, channel) ],
        [ :delete, project_notification_channel_path(project, channel) ],
        [ :post, test_project_notification_channel_path(project, channel) ],
        [ :delete, project_api_token_path(project, token) ] ].each do |verb, path|
        public_send(verb, path)
        expect(response).to have_http_status(:not_found), "#{verb} #{path} -> #{response.status}"
      end
      expect(Project.exists?(project.id)).to be(true)
      expect(NotificationChannel.exists?(channel.id)).to be(true)
      expect(ApiToken.exists?(token.id)).to be(true)
    end
  end

  describe "role is per project organization (Review Focus 2)" do
    it "uses the role in the project's organization, not the highest anywhere" do
      user = users.fetch("viewer")
      other = create(:organization)
      create(:membership, organization: other, user: user, role: "owner")
      sign_in(user)
      post project_api_tokens_path(project), params: { api_token: { name: "x" } }
      expect(response).to have_http_status(:forbidden)
      delete project_path(project)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "forbidden response" do
    before { act_as("viewer") }

    it "renders the copy for HTML" do
      post project_api_tokens_path(project), params: { api_token: { name: "x" } }
      expect(response.body).to include("You need the member role or higher to do this.")
    end

    it "is a bare 403 for JSON" do
      post project_api_tokens_path(project), params: { api_token: { name: "x" } }, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to be_empty
    end

    it "is a bare 403 for turbo_stream" do
      post project_api_tokens_path(project), params: { api_token: { name: "x" } },
                                             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:forbidden)
      expect(response.body).to be_empty
    end
  end

  describe "quarantines" do
    let(:test_case) { create(:test_case, project: project) }

    def create_quarantine
      Quarantine.quarantine!(test_case: test_case, user: users.fetch("owner"), reason: "Known flaky", days: 14)
    end

    it "lets viewers see the quarantine state, history and the quarantine page" do
      create_quarantine
      act_as("viewer")
      get project_test_case_path(project, test_case)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Quarantined until")
      expect(response.body).not_to include('value="Extend"', 'value="Release"', 'value="Quarantine"')
      get project_quarantined_tests_path(project)
      expect(response).to have_http_status(:ok)
    end

    it "forbids viewers to quarantine, extend or release" do
      act_as("viewer")
      post project_test_case_quarantines_path(project, test_case), params: { quarantine: { reason: "x", days: "7" } }
      expect(response).to have_http_status(:forbidden)
      quarantine = create_quarantine
      patch project_quarantine_path(project, quarantine), params: { quarantine: { days: "30" } }
      expect(response).to have_http_status(:forbidden)
      delete project_quarantine_path(project, quarantine)
      expect(response).to have_http_status(:forbidden)
      expect(quarantine.reload.released_at).to be_nil
      expect(quarantine.events.count).to eq(1)
    end

    %w[member admin owner].each do |role|
      it "lets #{role} quarantine, extend and release" do
        act_as(role)
        page = project_test_case_path(project, test_case, anchor: "quarantine")
        post project_test_case_quarantines_path(project, test_case), params: { quarantine: { reason: "Known flaky", days: "7" } }
        expect(response).to redirect_to(page)
        quarantine = test_case.quarantines.sole
        patch project_quarantine_path(project, quarantine), params: { quarantine: { days: "30", note: "still" } }
        expect(response).to redirect_to(page)
        delete project_quarantine_path(project, quarantine), params: { quarantine: { note: "fixed" } }
        expect(response).to redirect_to(page)
        expect(quarantine.events.order(:id).pluck(:action)).to eq(%w[quarantined extended released])
      end
    end

    it "returns 404 to outsiders on every quarantine route" do
      quarantine = create_quarantine
      sign_in(outsider)
      get project_quarantined_tests_path(project)
      expect(response).to have_http_status(:not_found)
      post project_test_case_quarantines_path(project, test_case), params: { quarantine: { reason: "x", days: "7" } }
      expect(response).to have_http_status(:not_found)
      patch project_quarantine_path(project, quarantine), params: { quarantine: { days: "7" } }
      expect(response).to have_http_status(:not_found)
      delete project_quarantine_path(project, quarantine)
      expect(response).to have_http_status(:not_found)
    end
  end
end
