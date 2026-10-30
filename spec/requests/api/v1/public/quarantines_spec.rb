require "rails_helper"

RSpec.describe "GET /api/v1/projects/:project_slug/quarantines", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user, name: "Demo") }
  let(:headers) { { "Authorization" => "Bearer #{PersonalToken.issue!(user: user, name: 'laptop', expires_in_days: 90).last}" } }

  def quarantines(slug: project.slug, **params)
    get api_v1_project_quarantines_path(slug), params: params, headers: headers
    expect_documented_response
    response.parsed_body
  end

  it "lists active quarantines by expiry" do
    a = create(:test_case, project: project, full_name: "A")
    b = create(:test_case, project: project, full_name: "B")
    later = Quarantine.quarantine!(test_case: a, user: user, reason: "Flaky login", days: 30)
    sooner = Quarantine.quarantine!(test_case: b, user: user, reason: "Mail server", days: 7)
    Quarantine.quarantine!(test_case: create(:test_case, project: project), user: user, reason: "Fixed", days: 7).release!(user: user)
    create(:quarantine)

    body = quarantines

    expect(body["data"]).to eq([
      { "test_case_id" => b.id, "full_name" => "B", "reason" => "Mail server", "expires_at" => sooner.expires_at.utc.iso8601,
        "quarantined_by" => user.email_address, "created_at" => sooner.created_at.utc.iso8601 },
      { "test_case_id" => a.id, "full_name" => "A", "reason" => "Flaky login", "expires_at" => later.expires_at.utc.iso8601,
        "quarantined_by" => user.email_address, "created_at" => later.created_at.utc.iso8601 }
    ])
    expect(body["meta"]).to eq("page" => 1, "per_page" => 50, "total" => 2, "next_page" => nil)
  end

  it "shows a deleted quarantiner as null" do
    quarantine = create(:quarantine, test_case: create(:test_case, project: project))
    quarantine.update_columns(created_by_id: nil)
    expect(quarantines["data"].sole["quarantined_by"]).to be_nil
  end
end
