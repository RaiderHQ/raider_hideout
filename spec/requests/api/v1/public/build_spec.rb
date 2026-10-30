require "rails_helper"

RSpec.describe "GET /api/v1/projects/:project_slug/builds/:id", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-10-25 12:00:00") }
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user, name: "Demo") }
  let(:headers) { { "Authorization" => "Bearer #{PersonalToken.issue!(user: user, name: 'laptop', expires_in_days: 90).last}" } }
  let(:login) { create(:test_case, project: project, full_name: "Login works", file_path: "spec/login_spec.rb", line_number: 3) }
  let(:checkout) { create(:test_case, project: project, full_name: "Checkout pays", file_path: "spec/checkout_spec.rb", line_number: 8) }

  around { |example| travel_to(now) { example.run } }

  def fetch(id, slug: project.slug, **params)
    get api_v1_project_build_path(slug, id), params: params, headers: headers
    expect_documented_response
    response.parsed_body
  end

  def expect_not_found
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).to eq("error" => "not found")
  end

  it "adds the gate, the comparison with the baseline, failures, shards and results_purged" do
    baseline = create(:build, project: project, branch: "main", created_at: 1.day.ago)
    baseline_run = create(:run, project: project, build: baseline, flakiness_analyzed_at: 1.day.ago)
    create(:test_result, run: baseline_run, test_case: login, status: "passed")
    create(:test_result, run: baseline_run, test_case: checkout, status: "failed")
    build = create(:build, project: project, branch: "main", status: "failed", total_count: 2, failed_count: 1,
                           quarantined_count: 1, created_at: 1.hour.ago)
    run = create(:run, project: project, build: build, shard_index: 1, shard_total: 1, shard_label: "rspec#1", status: "failed",
                       total_count: 2, failed_count: 1, quarantined_count: 1, flakiness_analyzed_at: 1.hour.ago)
    group = create(:error_group, project: project)
    create(:test_result, run: run, test_case: login, status: "failed", exception_class: "RuntimeError", failure_message: "x" * 1_500,
                         backtrace: "/gems/rspec-core/lib/rspec/core.rb:1\nspec/login_spec.rb:5:in `block (2 levels)'",
                         attempts: 2, error_group: group)
    create(:test_result, run: run, test_case: checkout, status: "quarantined", failure_message: "still broken")
    build.update_columns(baseline_build_id: baseline.id, baseline_assigned_at: now, gate_status: "failed", gate_evaluated_at: now,
                         gate_result: JSON.generate("rules" => { "pass_rate" => { "min" => 98, "actual" => 0, "outcome" => "failed" } }))

    body = fetch(build.id)

    expect(body["gate"]).to eq("state" => "failed", "rules" => [ { "rule" => "pass_rate", "outcome" => "failed", "detail" => "0% < 98%" } ])
    expect(body["comparison"]).to eq(
      "available" => true, "baseline_build_id" => baseline.id, "branch" => "main",
      "counts" => { "new_failures" => 1, "still_failing" => 0, "fixed" => 0, "new_tests" => 0 },
      "new_failure_test_ids" => [ login.id ], "still_failing_test_ids" => []
    )
    expect(body["failures"]).to eq([
      { "test_case_id" => login.id, "full_name" => "Login works", "file_path" => "spec/login_spec.rb", "line_number" => 3,
        "status" => "failed", "exception_class" => "RuntimeError", "message" => "x" * 1_000, "error_group_id" => group.id,
        "attempts" => 2, "app_frame" => "spec/login_spec.rb:5:in `block (2 levels)'" },
      { "test_case_id" => checkout.id, "full_name" => "Checkout pays", "file_path" => "spec/checkout_spec.rb", "line_number" => 8,
        "status" => "quarantined", "exception_class" => nil, "message" => "still broken", "error_group_id" => nil,
        "attempts" => 1, "app_frame" => nil }
    ])
    expect(body["shards"]).to eq([
      { "index" => 1, "total" => 1, "label" => "rspec#1", "status" => "failed",
        "counts" => { "total" => 2, "passed" => 0, "failed" => 1, "skipped" => 0, "pending" => 0, "flaky" => 0, "quarantined" => 1 } }
    ])
    expect(body["results_purged"]).to be(false)

    get api_v1_project_builds_path(project.slug), headers: headers
    expect_documented_response
    list_entry = response.parsed_body["data"].find { |entry| entry["id"] == build.id }
    expect(body.except("gate", "comparison", "failures", "shards", "results_purged")).to eq(list_entry)
  end

  it "prefers the stored app_frame over the backtrace fallback" do
    build = create(:build, project: project)
    run = create(:run, project: project, build: build)
    create(:test_result, run: run, status: "failed", backtrace: "spec/old_spec.rb:5:in 'x'", app_frame: "spec/new_spec.rb:9:in 'y'")
    create(:test_result, run: run, status: "failed", backtrace: "spec/old_spec.rb:5:in 'x'", app_frame: nil)

    frames = fetch(build.id)["failures"].map { |f| f["app_frame"] }

    expect(frames).to contain_exactly("spec/new_spec.rb:9:in 'y'", "spec/old_spec.rb:5:in 'x'")
    expect_documented_response
  end

  it "keeps at most 200 failures" do
    build = create(:build, project: project)
    run = create(:run, project: project, build: build)
    201.times { create(:test_result, run: run, status: "failed") }
    expect(fetch(build.id)["failures"].size).to eq(200)
  end

  it "marks purged results, with no failures and no comparison" do
    baseline = create(:build, project: project, created_at: 1.day.ago)
    create(:run, project: project, build: baseline, flakiness_analyzed_at: 1.day.ago)
    build = create(:build, project: project)
    create(:run, project: project, build: build, results_purged_at: 1.hour.ago, flakiness_analyzed_at: 2.hours.ago)
    build.update_columns(baseline_build_id: baseline.id, baseline_assigned_at: now)

    body = fetch(build.id)

    expect(body["results_purged"]).to be(true)
    expect(body["failures"]).to eq([])
    expect(body["comparison"]).to eq("available" => false, "baseline_build_id" => nil, "branch" => nil, "counts" => nil,
                                     "new_failure_test_ids" => nil, "still_failing_test_ids" => nil)
  end

  it "resolves latest on the default branch, or on the given branch" do
    main = create(:build, project: project, branch: "main", created_at: 2.hours.ago)
    create(:build, project: project, branch: "main", created_at: 3.hours.ago)
    feature = create(:build, project: project, branch: "feature/x", created_at: 1.hour.ago)

    expect(fetch("latest")["id"]).to eq(main.id)
    expect(fetch("latest", branch: "feature/x")["id"]).to eq(feature.id)
  end

  it "404s for latest on a branch without builds and in a project without builds (Review Focus 3)" do
    create(:build, project: project, branch: "main")
    fetch("latest", branch: "release")
    expect_not_found

    empty = create(:project, owner: user, name: "Empty")
    fetch("latest", slug: empty.slug)
    expect_not_found
  end

  it "400s for an id that is neither a number nor latest" do
    expect(fetch("newest")).to eq("error" => "invalid parameters", "details" => [ %(build_id must be an integer or "latest") ])
    expect(response).to have_http_status(:bad_request)
  end

  it "404s for another project's build and another organization's project" do
    other = create(:build)
    fetch(other.id)
    expect_not_found
    fetch(other.id, slug: other.project.slug)
    expect_not_found
    fetch(999_999)
    expect_not_found
  end
end
