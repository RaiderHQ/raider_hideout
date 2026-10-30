require "rails_helper"

RSpec.describe "GET /api/v1/builds/gate", type: :request do
  let(:project) { create(:project) }
  let!(:plaintext) { ApiToken.issue!(project: project, name: "CI").last }
  let(:headers) { { "Authorization" => "Bearer #{plaintext}" } }
  let(:build) { create(:build, project: project, build_key: "gh:1", status: "passed", expected_shards: 2) }

  def gate(key = build.build_key)
    get "/api/v1/builds/gate", params: { build_key: key }, headers: headers
    response.parsed_body
  end

  def verdict!(status, rules)
    build.update_columns(gate_status: status, gate_result: JSON.generate("rules" => rules), gate_evaluated_at: Time.current)
  end

  it "is pending while the build is incomplete, with the shard counts and the build URL" do
    build.update_columns(status: "incomplete")
    create(:run, project: project, build: build)

    expect(gate).to eq("state" => "pending", "build_state" => "incomplete", "shards" => { "received" => 1, "expected" => 2 },
                       "rules" => [], "url" => "http://www.example.com/projects/#{project.slug}/builds/#{build.id}")
    expect(response).to have_http_status(:ok)
  end

  it "stays pending when every shard is in but flakiness is not yet analysed (Review Focus 3)" do
    create(:run, project: project, build: build, flakiness_analyzed_at: Time.current)
    create(:run, project: project, build: build)
    expect(build.reload).to be_complete
    expect(build).not_to be_ready_to_notify

    expect(gate).to include("state" => "pending", "build_state" => "passed", "shards" => { "received" => 2, "expected" => 2 })
  end

  it "reports an unknown shard total as null (Review Focus 2)" do
    build.update_columns(expected_shards: nil)
    create(:run, project: project, build: build)
    expect(gate["shards"]).to eq("received" => 1, "expected" => nil)
  end

  it "returns none with no rules" do
    verdict!("none", {})
    expect(gate).to include("state" => "none", "rules" => [])
  end

  it "lists a failed verdict's rules in rule order with their details" do
    verdict!("failed", "new_flaky" => { "count" => 0, "outcome" => "passed" },
                       "pass_rate" => { "min" => 98, "actual" => 96, "outcome" => "failed" },
                       "new_failures" => { "count" => 2, "baseline_build_id" => 41, "branch" => "main", "outcome" => "failed" })

    expect(gate).to include("state" => "failed", "rules" => [
      { "rule" => "pass_rate", "outcome" => "failed", "detail" => "96% < 98%" },
      { "rule" => "new_failures", "outcome" => "failed", "detail" => "2 new failures vs main" },
      { "rule" => "new_flaky", "outcome" => "passed", "detail" => "0 new flaky tests" }
    ])
  end

  it "uses ≥ for a passed rate, singular nouns for one, and the reason for a skipped rule" do
    verdict!("failed", "pass_rate" => { "min" => 98, "actual" => 99, "outcome" => "passed" },
                       "new_failures" => { "outcome" => "skipped", "reason" => "no baseline build on main" },
                       "new_flaky" => { "count" => 1, "outcome" => "failed" })
    expect(gate["rules"].map { |rule| rule["detail"] }).to eq([ "99% ≥ 98%", "no baseline build on main", "1 new flaky test" ])

    verdict!("failed", "new_failures" => { "count" => 1, "baseline_build_id" => 41, "branch" => "main", "outcome" => "failed" })
    expect(gate["rules"].map { |rule| rule["detail"] }).to eq([ "1 new failure vs main" ])
  end

  it "returns 404 for an unknown build key and for another project's build" do
    other = create(:build, build_key: "gh:other")
    [ "nope", other.build_key ].each do |key|
      expect(gate(key)).to eq("error" => "build not found")
      expect(response).to have_http_status(:not_found)
    end
  end

  it "returns 401 without a token" do
    get "/api/v1/builds/gate", params: { build_key: build.build_key }
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
  end
end
