require "rails_helper"
require "rake"

RSpec.describe "Signing in as the demo user", type: :request do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "hideout:demo" } }

  it "lands on the projects list, not setup or email verification" do
    Hideout::Demo.load!
    FirstRun.reset!
    post session_path, params: { email_address: "demo@raider.test", password: "raider-demo-password" }
    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(request.path).to eq("/")
    expect(response.body).to include("Shop tests")
  end
end
