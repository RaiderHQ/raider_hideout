require "rails_helper"

RSpec.describe "First-run setup", type: :request do
  let(:code) { "ABCD-2345" }
  let(:params) do
    { code: code, instance_setup: { email_address: "admin@example.com", password: "password123",
                                     password_confirmation: "password123", organization_name: "Acme QA",
                                     project_name: "Checkout" } }
  end

  before do
    with_env("HIDEOUT_SETUP_CODE" => code)
    Rails.configuration.x.first_run_redirect = true
    FirstRun.reset!
  end

  after do
    Rails.configuration.x.first_run_redirect = false
    FirstRun.reset!
  end

  it "sends every HTML page to /setup while there are no users" do
    get new_session_path
    expect(response).to redirect_to(setup_path)
    get root_path
    expect(response).to redirect_to(setup_path)
  end

  it "leaves the API and the health check alone" do
    post "/api/v1/runs", headers: { "Authorization" => "Bearer rdr_nope" }
    expect(response).to have_http_status(:unauthorized)
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  it "shows the locked page as a 404 without the right code" do
    get setup_path
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Open the setup link printed in the server log")
    get setup_path(code: "WXYZ-2345")
    expect(response).to have_http_status(:not_found)
  end

  it "shows the form for the code as a person types it, without inline styles or handlers" do
    get setup_path(code: "abcd2345")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Set up Raider Hideout")
    expect(response.body).not_to match(/\sstyle=|\son[a-z]+=/)
  end

  it "creates the instance, signs the admin in and shows the CI settings once" do
    expect { post setup_path, params: params }.to change(User, :count).by(1).and change(ApiToken, :count).by(1)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("no-store")
    expect(response.body).to include("RAIDER_ENDPOINT=http://www.example.com")
    token = response.body[/RAIDER_TOKEN=(rdr_[^<\s]+)/, 1]
    project = Project.find_by!(name: "Checkout")
    expect(ApiToken.authenticate(token).project).to eq(project)
    get project_path(project)
    expect(response).to have_http_status(:ok)
  end

  it "re-renders the form with 422 on invalid input" do
    post setup_path, params: params.deep_merge(instance_setup: { password_confirmation: "different1" })
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Password confirmation doesn&#39;t match Password")
    expect(User.count).to eq(0)
  end

  it "refuses a POST without the code" do
    post setup_path, params: params.except(:code)
    expect(response).to have_http_status(:not_found)
    expect(User.count).to eq(0)
  end

  it "is a plain 404 for good once a user exists, and stops redirecting" do
    create(:user)
    get setup_path(code: code)
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Open the setup link")
    post setup_path, params: params
    expect(response).to have_http_status(:not_found)
    expect(User.count).to eq(1)
    get new_session_path
    expect(response).to have_http_status(:ok)
  end

  it "limits setup attempts to 10 per 3 minutes" do
    bad = params.deep_merge(instance_setup: { project_name: "" })
    10.times { post setup_path, params: bad }
    expect(response).to have_http_status(:unprocessable_content)
    post setup_path, params: bad
    expect(response).to have_http_status(:too_many_requests)
  end

  it "limits code guesses to 20 per 3 minutes, without counting visits that carry no code" do
    5.times { get setup_path }
    20.times { get setup_path(code: "WXYZ-2345") }
    expect(response).to have_http_status(:not_found)
    get setup_path(code: "WXYZ-2345")
    expect(response).to have_http_status(:too_many_requests)
  end

  it "keeps the setup code out of the log" do
    log = capture_log { get setup_path(code: "WXYZ-7777") }
    expect(log).not_to include("WXYZ-7777")
    expect(log).to include("[FILTERED]")
  end
end
