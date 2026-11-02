require "rails_helper"

# The fixture stands in for a raider_reporter 0.13 upload (failed-step spec §2).
RSpec.describe "Recorded steps end to end", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:ci_token) { ApiToken.issue!(project: project, name: "CI").last }
  let(:personal_token) { PersonalToken.issue!(user: user, name: "laptop", expires_in_days: 90).last }

  it "shows Failed at step 3 after a reporter upload" do
    post "/api/v1/runs", params: { payload: file_fixture("payloads/failed_steps.json").read },
                         headers: { "Authorization" => "Bearer #{ci_token}" }
    expect(response).to have_http_status(:created)
    run = project.runs.sole

    sign_in(user)
    get project_run_path(project, run)
    headline = Nokogiri::HTML(response.body).css("[data-testid=steps-headline]").text.squish
    expect(headline).to eq("Failed at step 3: Click \"Save\"")

    get api_v1_project_build_path(project.slug, run.build_id), headers: { "Authorization" => "Bearer #{personal_token}" }
    expect_documented_response
    failure = response.parsed_body["failures"].sole
    expect(failure["steps"]["failed"]).to eq(2)
  end
end
