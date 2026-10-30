require "rails_helper"

RSpec.describe "Personal API: tests", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-25 12:00:00") }
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user, name: "Demo") }
  let(:headers) { { "Authorization" => "Bearer #{PersonalToken.issue!(user: user, name: 'laptop', expires_in_days: 90).last}" } }
  let(:login) do
    create(:test_case, project: project, full_name: "Login works", file_path: "spec/login_spec.rb", line_number: 3, last_status: "failed")
  end

  around { |example| travel_to(now) { example.run } }

  def tests(slug: project.slug, **params)
    get api_v1_project_tests_path(slug), params: params, headers: headers
    expect_documented_response
    response.parsed_body
  end

  def detail(id, slug: project.slug)
    get api_v1_project_test_path(slug, id), headers: headers
    expect_documented_response
    response.parsed_body
  end

  describe "GET /api/v1/projects/:project_slug/tests" do
    let!(:checkout) { create(:test_case, project: project, full_name: "Checkout pays", file_path: "spec/checkout_spec.rb") }

    before do
      search_result(login, status: "passed", at: 2.days.ago, duration: 100)
      search_result(login, status: "failed", at: 1.day.ago, duration: 300)
      search_result(checkout, status: "passed", at: 1.day.ago)
      create(:test_case_verdict, test_case: login, branch: "main", flaky: true)
      create(:quarantine, test_case: login)
    end

    it "searches with Explore syntax and returns the canonical query and the notices verbatim (Review Focus 4)" do
      body = tests(q: "status:failed foo:bar")

      expect(body["data"]).to eq([
        { "id" => login.id, "full_name" => "Login works", "file_path" => "spec/login_spec.rb", "line_number" => 3,
          "last_status" => "failed", "pass_rate" => 50, "failures" => 1, "avg_duration_ms" => 200,
          "last_run_at" => 1.day.ago.utc.iso8601, "flaky" => true, "quarantined" => true }
      ])
      expect(body["meta"]).to eq("page" => 1, "per_page" => 50, "total" => 1, "next_page" => nil, "query" => "status:failed",
                                 "notices" => [ %(Ignored "foo:bar": unknown filter) ])
    end

    it "lists every test that ran on the default branch in the last 7 days without a query" do
      body = tests
      expect(body["data"].map { |test| test["id"] }).to contain_exactly(login.id, checkout.id)
      expect(body["meta"]).to include("total" => 2, "query" => "", "notices" => [])
    end

    it "pages, and rejects bad paging" do
      expect(tests(per_page: 1)["meta"]).to include("total" => 2, "next_page" => 2)
      expect(tests(per_page: 1, page: 3)["data"]).to eq([])
      expect(tests(per_page: 500)).to eq("error" => "invalid parameters", "details" => [ "per_page must be an integer from 1 to 100" ])
      expect(response).to have_http_status(:bad_request)
    end

    it "404s for another organization's project" do
      expect(tests(slug: create(:project).slug)).to eq("error" => "not found")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/projects/:project_slug/tests/:id" do
    it "adds the last 20 results on any branch, the verdicts, the active quarantine and its events" do
      feature = search_result(login, status: "passed", branch: "feature/x", at: 3.days.ago, duration: 50)
      failed = search_result(login, status: "failed", at: 1.day.ago, duration: 300, message: "m" * 400)
      create(:test_case_verdict, test_case: login, branch: "main", flaky: true, flaky_reason: "flips", flip_rate: 0.4, sample_count: 12)
      quarantine = Quarantine.quarantine!(test_case: login, user: user, reason: "Known flaky", days: 14)

      body = detail(login.id)

      expect(body.slice("id", "full_name", "file_path", "line_number", "last_status", "pass_rate", "failures",
                        "avg_duration_ms", "last_run_at", "flaky", "quarantined")).to eq(
        "id" => login.id, "full_name" => "Login works", "file_path" => "spec/login_spec.rb", "line_number" => 3,
        "last_status" => "failed", "pass_rate" => 0, "failures" => 1, "avg_duration_ms" => 300,
        "last_run_at" => 1.day.ago.utc.iso8601, "flaky" => true, "quarantined" => true
      )
      expect(body["results"]).to eq([
        { "build_id" => failed.run.build_id, "run_id" => failed.run_id, "branch" => "main", "status" => "failed",
          "duration_ms" => 300, "message" => "m" * 300, "created_at" => 1.day.ago.utc.iso8601 },
        { "build_id" => feature.run.build_id, "run_id" => feature.run_id, "branch" => "feature/x", "status" => "passed",
          "duration_ms" => 50, "message" => nil, "created_at" => 3.days.ago.utc.iso8601 }
      ])
      expect(body["verdicts"]).to eq([ { "branch" => "main", "flaky" => true, "flaky_reason" => "flips", "flip_rate" => 0.4, "sample_count" => 12 } ])
      expect(body["quarantine"]).to eq("reason" => "Known flaky", "expires_at" => quarantine.expires_at.utc.iso8601,
                                       "quarantined_by" => user.email_address)
      expect(body["quarantine_events"]).to eq([ { "action" => "quarantined", "note" => nil, "actor" => user.email_address,
                                                  "created_at" => now.utc.iso8601 } ])
    end

    it "keeps the last 20 results" do
      21.times { |i| search_result(login, status: "passed", at: (i + 1).hours.ago) }
      expect(detail(login.id)["results"].size).to eq(20)
    end

    it "falls back to the stored status when the test did not run on the default branch in the last 7 days" do
      old = create(:test_case, project: project, last_status: "passed")
      search_result(old, status: "passed", at: 10.days.ago)

      expect(detail(old.id).slice("last_status", "pass_rate", "failures", "avg_duration_ms", "last_run_at", "flaky", "quarantined", "quarantine"))
        .to eq("last_status" => "passed", "pass_rate" => nil, "failures" => 0, "avg_duration_ms" => nil, "last_run_at" => nil,
               "flaky" => false, "quarantined" => false, "quarantine" => nil)
    end

    it "404s for another project's test, an unknown id and another organization's project" do
      other = create(:test_case)
      [ [ project.slug, other.id ], [ project.slug, "abc" ], [ project.slug, "#{login.id}abc" ], [ other.project.slug, other.id ] ].each do |slug, id|
        expect(detail(id, slug: slug)).to eq("error" => "not found")
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
