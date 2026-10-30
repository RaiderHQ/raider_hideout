require "rails_helper"

RSpec.describe "Personal API: error groups", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-25 12:00:00") }
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user, name: "Demo") }
  let(:headers) { { "Authorization" => "Bearer #{PersonalToken.issue!(user: user, name: 'laptop', expires_in_days: 90).last}" } }

  around { |example| travel_to(now) { example.run } }

  def groups(slug: project.slug, **params)
    get api_v1_project_errors_path(slug), params: params, headers: headers
    expect_documented_response
    response.parsed_body
  end

  def group(id, slug: project.slug)
    get api_v1_project_error_path(slug, id), headers: headers
    expect_documented_response
    response.parsed_body
  end

  def fail_into(error_group, test_case, at:)
    search_result(test_case, status: "failed", at: at).update!(error_group: error_group)
  end

  describe "GET /api/v1/projects/:project_slug/errors" do
    it "lists groups seen in the window, last seen first, with the tests affected in that window" do
      recent = create(:error_group, project: project, exception_class: "Net::ReadTimeout", sample_message: "s" * 400,
                                    frame: "spec/a_spec.rb:3", first_seen_at: 20.days.ago, last_seen_at: 1.day.ago)
      older = create(:error_group, project: project, first_seen_at: 25.days.ago, last_seen_at: 10.days.ago)
      create(:error_group, project: project, first_seen_at: 60.days.ago, last_seen_at: 40.days.ago)
      create(:error_group, last_seen_at: 1.day.ago)
      2.times { |i| fail_into(recent, create(:test_case, project: project), at: (i + 1).days.ago) }

      body = groups

      expect(body["data"].map { |entry| entry["id"] }).to eq([ recent.id, older.id ])
      expect(body["data"].first).to eq(
        "id" => recent.id, "exception_class" => "Net::ReadTimeout", "sample_message" => "s" * 300, "frame" => "spec/a_spec.rb:3",
        "first_seen_at" => 20.days.ago.utc.iso8601, "last_seen_at" => 1.day.ago.utc.iso8601, "affected_tests" => 2
      )
      expect(body["data"].last["affected_tests"]).to eq(0)
      expect(body["meta"]).to eq("page" => 1, "per_page" => 50, "total" => 2, "next_page" => nil)
      expect(groups(since: "7d")["data"].map { |entry| entry["id"] }).to eq([ recent.id ])
      expect(groups(since: "90d")["meta"]["total"]).to eq(3)
    end

    it "rejects an unknown window" do
      expect(groups(since: "1y")).to eq("error" => "invalid parameters", "details" => [ "since must be one of 24h, 7d, 30d, 90d" ])
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/projects/:project_slug/errors/:id" do
    it "adds up to 50 affected tests, most recently failed first" do
      error_group = create(:error_group, project: project)
      a = create(:test_case, project: project, full_name: "A", file_path: "spec/a_spec.rb")
      b = create(:test_case, project: project, full_name: "B", file_path: "spec/b_spec.rb")
      fail_into(error_group, a, at: 3.days.ago)
      fail_into(error_group, b, at: 1.day.ago)
      search_result(a, status: "passed", at: 1.hour.ago)

      expect(group(error_group.id)).to eq(
        "id" => error_group.id, "exception_class" => "RuntimeError", "sample_message" => nil, "frame" => "",
        "first_seen_at" => now.utc.iso8601, "last_seen_at" => now.utc.iso8601, "affected_tests" => 2,
        "tests" => [
          { "test_case_id" => b.id, "full_name" => "B", "file_path" => "spec/b_spec.rb", "last_seen_at" => 1.day.ago.utc.iso8601 },
          { "test_case_id" => a.id, "full_name" => "A", "file_path" => "spec/a_spec.rb", "last_seen_at" => 3.days.ago.utc.iso8601 }
        ]
      )
    end

    it "404s for another project's group and another organization's project" do
      other = create(:error_group)
      loose = create(:error_group, project: project)
      [ [ project.slug, other.id ], [ other.project.slug, other.id ], [ project.slug, "#{loose.id}abc" ] ].each do |slug, id|
        expect(group(id, slug: slug)).to eq("error" => "not found")
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
