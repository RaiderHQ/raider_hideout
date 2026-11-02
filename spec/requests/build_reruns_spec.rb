require "rails_helper"

RSpec.describe "Build re-runs", type: :request do
  let(:org) { create(:organization) }
  let(:project) { create(:project, organization: org) }
  let(:token) { "ghp_#{'c' * 36}" }
  let!(:access) { CiAccess.create!(project: project, token: token, token_saved_at: Time.current) }
  let(:build_record) do
    create(:build, project: project, provider: "github_actions", status: "failed",
                   ci_run_key: "github_actions:octo/hello:123", latest_attempt: 1)
  end
  let(:url) { "https://api.github.com/repos/octo/hello/actions/runs/123/rerun-failed-jobs" }
  let(:users) do
    Membership::ROLES.index_with do |role|
      create(:user).tap { |u| create(:membership, organization: org, user: u, role: role) }
    end
  end

  def post_rerun(build = build_record, **params) = post(project_build_rerun_path(project, build), params: params)

  it "forbids a viewer and makes no request" do
    sign_in(users.fetch("viewer"))
    stub = stub_request(:any, /api\.github\.com/)
    post_rerun
    expect(response).to have_http_status(:forbidden)
    expect(stub).not_to have_been_requested
    expect(BuildRerun.count).to eq(0)
  end

  it "404s a build of another organization" do
    sign_in(users.fetch("member"))
    other = create(:build, project: create(:project), provider: "github_actions", status: "failed",
                           ci_run_key: "github_actions:octo/hello:123")
    stub = stub_request(:any, /api\.github\.com/)
    post project_build_rerun_path(project, other)
    expect(response).to have_http_status(:not_found)
    expect(stub).not_to have_been_requested
  end

  it "redirects to the build with the accepted flash" do
    sign_in(users.fetch("member"))
    stub_request(:post, url).to_return(status: 201, body: "")
    post_rerun
    expect(response).to redirect_to(project_build_path(project, build_record))
    expect(flash[:notice]).to eq("Re-run requested. The result arrives as attempt 2.")
    expect(BuildRerun.last).to have_attributes(user: users.fetch("member"), status: "accepted")
  end

  it "redirects with the error copy as an alert when GitHub rejects" do
    sign_in(users.fetch("member"))
    stub_request(:post, url).to_return(status: 403, body: '{"message":"nope"}')
    post_rerun
    expect(response).to redirect_to(project_build_path(project, build_record))
    expect(flash[:alert]).to eq("GitHub refused: the token needs Actions: Read and write for this repository.")
    expect(flash[:notice]).to be_nil
  end

  it "shows the guard copy on a second tap and calls GitHub once" do
    sign_in(users.fetch("member"))
    stub = stub_request(:post, url).to_return(status: 201, body: "")
    post_rerun
    post_rerun
    expect(stub).to have_been_requested.once
    expect(flash[:alert]).to match(/\AA re-run was already requested at \d\d:\d\d\.\z/)
  end

  describe "return_to" do
    before do
      sign_in(users.fetch("member"))
      stub_request(:post, url).to_return(status: 201, body: "")
    end

    it "honours a test result anchor" do
      post_rerun(return_to: "#test_result_42")
      expect(response).to redirect_to(project_build_path(project, build_record, anchor: "test_result_42"))
    end

    [ "https://evil.example/", "//evil.example", "/projects", "#test_result_", "#test_result_1x", "#other_1", "#test_result_1\n#x", "javascript:alert(1)" ].each do |value|
      it "ignores #{value.inspect}" do
        post_rerun(return_to: value)
        expect(response).to redirect_to(project_build_path(project, build_record))
      end
    end
  end

  it "requires a CSRF token" do
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    sign_in(users.fetch("member"))
    stub = stub_request(:any, /api\.github\.com/)
    post_rerun
    expect(stub).not_to have_been_requested
    expect(BuildRerun.count).to eq(0)
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  describe "build page" do
    before { sign_in(users.fetch("member")) }

    it "lists re-runs newest first, five at most, with the starter and outcome copy" do
      starter = create(:user, email_address: "starter@example.com")
      create(:membership, organization: org, user: starter, role: "member")
      6.times do |i|
        build_record.reruns.create!(user: starter, attempt_before: i, status: "rejected", http_status: 404, created_at: (i + 1).hours.ago)
      end
      gone = build_record.reruns.create!(user: nil, attempt_before: 0, status: "accepted", http_status: 201, created_at: 30.minutes.ago)
      get project_build_path(project, build_record)
      rows = response.body.scan(/Re-run requested by [^<]+/)
      expect(rows.size).to eq(5)
      expect(rows.first).to include("someone", "GitHub accepted")
      expect(rows.last).to include("starter@example.com", "GitHub can&#39;t find this run, or the token can&#39;t see the repository.")
      expect(gone).to be_persisted
    end

    it "shows waiting copy for a pending row and the pending line instead of the button" do
      build_record.reruns.create!(user: users.fetch("member"), attempt_before: 1, status: "pending")
      get project_build_path(project, build_record)
      expect(response.body).to include("waiting for GitHub")
      expect(response.body).to match(/Re-run requested by #{Regexp.escape(users.fetch('member').email_address)} at \d\d:\d\d\./)
      expect(response.body).not_to include('value="Re-run failed"')
    end

    it "runs a bounded number of queries however many failed cards there are" do
      run = create(:run, project: project, build: build_record)
      3.times { create(:test_result, run: run, status: "failed") }
      get project_build_path(project, build_record)
      few = ci_queries { get project_build_path(project, build_record) }
      3.times { create(:test_result, run: run, status: "failed") }
      many = ci_queries { get project_build_path(project, build_record) }
      expect(many).to eq(few)
    end
  end

  def ci_queries
    count = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      count += 1 if payload[:sql] =~ /ci_accesses|build_reruns/
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(sub)
  end
end
