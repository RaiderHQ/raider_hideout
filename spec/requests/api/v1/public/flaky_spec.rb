require "rails_helper"

RSpec.describe "GET /api/v1/projects/:project_slug/flaky", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user, name: "Demo") }
  let(:headers) { { "Authorization" => "Bearer #{PersonalToken.issue!(user: user, name: 'laptop', expires_in_days: 90).last}" } }

  def flaky(slug: project.slug, **params)
    get api_v1_project_flaky_path(slug), params: params, headers: headers
    expect_documented_response
    response.parsed_body
  end

  it "lists flaky tests on the default branch by flip rate, or on the given branch" do
    a = create(:test_case, project: project, full_name: "A", file_path: "spec/a_spec.rb")
    b = create(:test_case, project: project, full_name: "B", file_path: "spec/b_spec.rb")
    since = create(:build, project: project, branch: "main")
    create(:test_case_verdict, test_case: a, branch: "main", flaky: true, flip_rate: 0.3, flaky_reason: "flips",
                               sample_count: 10, flaky_since_build: since)
    create(:test_case_verdict, test_case: b, branch: "main", flaky: true, flip_rate: 0.6, flaky_reason: "retry", sample_count: 8)
    create(:test_case_verdict, test_case: create(:test_case, project: project), branch: "main", flaky: false)
    create(:test_case_verdict, test_case: a, branch: "feature/x", flaky: true, flip_rate: 0.5)
    create(:test_case_verdict, test_case: create(:test_case), branch: "main", flaky: true)

    body = flaky

    expect(body["data"]).to eq([
      { "test_case_id" => b.id, "full_name" => "B", "file_path" => "spec/b_spec.rb", "flip_rate" => 0.6, "flaky_reason" => "retry",
        "sample_count" => 8, "flaky_since_build_id" => nil },
      { "test_case_id" => a.id, "full_name" => "A", "file_path" => "spec/a_spec.rb", "flip_rate" => 0.3, "flaky_reason" => "flips",
        "sample_count" => 10, "flaky_since_build_id" => since.id }
    ])
    expect(body["meta"]).to eq("page" => 1, "per_page" => 50, "total" => 2, "next_page" => nil)
    expect(flaky(branch: "feature/x")["data"].map { |entry| entry["test_case_id"] }).to eq([ a.id ])
    expect(flaky(per_page: 1, page: 2)["data"].map { |entry| entry["test_case_id"] }).to eq([ a.id ])
  end

  it "404s for another organization's project" do
    expect(flaky(slug: create(:project).slug)).to eq("error" => "not found")
    expect(response).to have_http_status(:not_found)
  end
end
