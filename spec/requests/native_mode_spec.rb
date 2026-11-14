require "rails_helper"

RSpec.describe "Native app mode", type: :request do
  let(:org) { create(:organization, name: "Acme") }
  let(:project) { create(:project, organization: org, name: "Shop tests") }
  let(:user) { create(:user).tap { |u| create(:membership, organization: org, user: u, role: "owner") } }
  let(:build_record) { create(:build, project: project) }
  let(:test_case) { create(:test_case, project: project, full_name: "Checkout pays by card") }
  let(:browser) { { "HTTP_USER_AGENT" => NativeHelpers::BROWSER_AGENT } }

  def title = response.body[%r{<title>(.*?)</title>}m, 1]

  def pages
    {
      projects_path => "Projects",
      project_path(project) => "Shop tests",
      project_builds_path(project) => "Builds",
      project_build_path(project, build_record) => "Build ##{build_record.id}",
      project_test_case_path(project, test_case) => "Checkout pays by card",
      project_ci_access_path(project) => "CI access",
      account_path => "Account"
    }
  end

  describe "with the Raider app's iOS user agent" do
    before { sign_in(user) }

    it "drops the top web nav, marks the body and uses the short titles" do
      CiAccess.create!(project: project, token: "ghp_#{'a' * 36}", token_saved_at: Time.current, repository: "a/b", workflow: "x.yml")
      pages.merge(new_project_run_request_path(project) => "Run tests").each do |path, short|
        get path, headers: as_hotwire_native_ios
        expect(response).to have_http_status(:ok), path
        expect(response.body).to include('data-native="ios"')
        expect(response.body).not_to include("shadow-nav", 'id="account-menu"', 'id="organization-menu"')
        expect(title).to eq(short), path
      end
    end

    it "keeps the project breadcrumb, which is content" do
      get project_path(project), headers: as_hotwire_native_ios
      expect(response.body).to include('aria-label="Breadcrumb"')
    end

    it "shows the server on the account page and no phone notifications link" do
      get account_path, headers: as_hotwire_native_ios
      expect(response.body).to include("Server: www.example.com", "Change server", %(href="#{account_server_path}"), "Tokens", "Sign out", "Acme")
      expect(response.body).not_to include("Phone notifications")
    end

    it "shows only the later-version copy on the phone notifications page" do
      get phone_notifications_path, headers: as_hotwire_native_ios
      expect(response.body).to include("Notifications in the Raider app come in a later version. " \
                                       "To get them now, open this server in Safari and add it to your Home Screen.")
      expect(response.body).not_to include("Turn on notifications", "Your devices")
    end

    it "marks the Android app" do
      get projects_path, headers: { "HTTP_USER_AGENT" => NativeHelpers::ANDROID_AGENT }
      expect(response.body).to include('data-native="android"')
      expect(response.body).not_to include("shadow-nav")
    end
  end

  describe "with the trace page" do
    it "keeps the browser title and gives the app the short one" do
      sign_in(user)
      run = create(:run, project: project, build: build_record)
      result = create(:test_result, run: run, test_case: test_case)
      trace = attach_trace(result, io: StringIO.new(file_fixture("trace-v1.zip").binread))
      get test_result_trace_path(result, trace), headers: browser
      expect(title).to eq("Trace · Checkout pays by card")
      get test_result_trace_path(result, trace), headers: as_hotwire_native_ios
      expect(title).to eq("Trace")
    end
  end

  describe "with a browser user agent" do
    before { sign_in(user) }

    it "keeps the nav and today's titles" do
      get projects_path, headers: browser
      expect(response.body).to include("shadow-nav", 'id="account-menu"')
      expect(response.body).not_to include("data-native")
      expect(title).to eq("Raider Hideout")
      get account_path, headers: browser
      expect(title).to eq("Account · Raider Hideout")
    end

    it "adds Account at the top of the account menu" do
      get projects_path, headers: browser
      menu = response.body[%r{<details id="account-menu".*?</details>}m]
      expect(menu.index(">Account</a>")).to be < menu.index(">Tokens</a>")
    end

    it "shows tokens, phone notifications and sign out on the account page, and no server line" do
      get account_path, headers: browser
      expect(response.body).to include("Tokens", "Phone notifications", "Sign out")
      expect(response.body).not_to include("Server:", "Change server")
    end

    it "explains the server page" do
      get account_server_path, headers: browser
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Server address is only used by the Raider app.")
    end
  end

  it "serves the iOS 17.2 app and refuses 17.1, as allow_browser :modern does" do
    sign_in(user)
    get projects_path, headers: as_hotwire_native_ios("17_2")
    expect(response).to have_http_status(:ok)
    get projects_path, headers: as_hotwire_native_ios("17_1")
    expect(response).to have_http_status(:not_acceptable)
  end

  it "sends a signed-out visitor to sign in" do
    get account_path, headers: as_hotwire_native_ios
    expect(response).to redirect_to(new_session_path)
    get new_session_path, headers: as_hotwire_native_ios
    expect(title).to eq("Sign in")
  end
end
