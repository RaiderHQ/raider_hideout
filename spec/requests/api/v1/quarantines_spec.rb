require "rails_helper"

RSpec.describe "GET /api/v1/quarantine", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:project) { create(:project) }
  let!(:plaintext) { ApiToken.issue!(project: project, name: "CI").last }
  let(:headers) { { "Authorization" => "Bearer #{plaintext}" } }
  let(:user) { create(:user) }
  let(:now) { Time.zone.parse("2026-10-24 12:00:00") }

  around { |example| travel_to(now) { example.run } }

  def quarantine(name, days: 14, target_project: project)
    test_case = create(:test_case, project: target_project, full_name: name)
    Quarantine.quarantine!(test_case: test_case, user: user, reason: "flaky", days: days)
  end

  it "lists the token project's active quarantines by test_key with ISO 8601 expiry" do
    first = quarantine("Checkout pays", days: 7)
    second = quarantine("Login works", days: 30)

    get "/api/v1/quarantine", headers: headers

    expect(response).to have_http_status(:ok)
    expected = [ first, second ].sort_by { |q| q.test_case.test_key }.map do |q|
      { "test_key" => q.test_case.test_key, "expires_at" => q.expires_at.utc.iso8601 }
    end
    expect(response.parsed_body).to eq("quarantined" => expected)
    expect(response.parsed_body["quarantined"].first["expires_at"]).to match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\z/)
  end

  it "leaves out released, expired and other projects' quarantines" do
    quarantine("Released").release!(user: user)
    quarantine("Expires soon", days: 7)
    quarantine("Foreign", target_project: create(:project))
    travel 8.days

    get "/api/v1/quarantine", headers: headers

    expect(response.parsed_body).to eq("quarantined" => [])
  end

  it "returns 401 without a token or with a bad one" do
    get "/api/v1/quarantine"
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
    get "/api/v1/quarantine", headers: { "Authorization" => "Bearer rdr_wrong" }
    expect(response).to have_http_status(:unauthorized)
  end
end
