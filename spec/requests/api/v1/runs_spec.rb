require "rails_helper"

RSpec.describe "POST /api/v1/runs", type: :request do
  let(:project) { create(:project) }
  let!(:plaintext) { ApiToken.issue!(project: project, name: "CI").last }
  let(:headers) { { "Authorization" => "Bearer #{plaintext}" } }

  def post_run(data, files = {}, headers: self.headers)
    post "/api/v1/runs", params: { payload: data.to_json }.merge(files), headers: headers
  end

  it "creates a run and returns its URL" do
    post_run(build_payload)
    expect(response).to have_http_status(:created)
    body = response.parsed_body
    run = project.runs.sole
    expect(body).to eq("run_id" => run.id, "url" => "http://www.example.com/projects/#{project.slug}/runs/#{run.id}",
                       "build" => { "id" => run.build_id,
                                    "url" => "http://www.example.com/projects/#{project.slug}/builds/#{run.build_id}" })
  end

  it "returns the same build for shards sharing a build_key" do
    payloads = [ 1, 2 ].map do |index|
      build_payload.tap do |d|
        d["run"]["ci"]["build_key"] = "github_actions:acme/app:5:1"
        d["run"]["shard"] = { "index" => index, "total" => 2, "label" => "test##{index}" }
      end
    end
    build_ids = payloads.map do |data|
      post_run(data)
      expect(response).to have_http_status(:created)
      response.parsed_body.dig("build", "id")
    end
    expect(build_ids.uniq).to eq([ project.builds.sole.id ])
  end

  it "returns 200 for a duplicate client_run_id" do
    data = build_payload
    post_run(data)
    post_run(data)
    expect(response).to have_http_status(:ok)
    expect(project.runs.count).to eq(1)
    run = project.runs.sole
    expect(response.parsed_body["build"])
      .to eq("id" => run.build_id, "url" => "http://www.example.com/projects/#{project.slug}/builds/#{run.build_id}")
  end

  it "accepts any-case Bearer scheme with trailing whitespace" do
    post_run(build_payload, headers: { "Authorization" => "bearer #{plaintext}  " })
    expect(response).to have_http_status(:created)
  end

  it "rejects missing or wrong tokens" do
    post_run(build_payload, headers: {})
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).to eq("error" => "unauthorized")
    post_run(build_payload, headers: { "Authorization" => "Bearer rdr_wrong" })
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 422 with details for invalid payloads" do
    post_run(build_payload(schema_version: 3))
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["details"]).to eq([ "unsupported schema_version 3; supported: 1, 2" ])
  end

  it "returns 422 when the payload part is missing" do
    post "/api/v1/runs", params: {}, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 422 for unparsable timestamps instead of crashing" do
    data = build_payload
    data["run"]["finished_at"] = "not a time"
    post_run(data)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 413 for oversized requests" do
    stub_const("Api::V1::RunsController::MAX_REQUEST_BYTES", 10)
    post_run(build_payload)
    expect(response).to have_http_status(413)
    expect(response.parsed_body).to eq("error" => "payload too large")
  end

  it "returns 413 for oversized attachments" do
    stub_const("Ingest::MAX_ATTACHMENT_BYTES", 2)
    data = build_payload(results: [ build_result("attachments" => [ { "name" => "s", "part" => "att_0", "content_type" => "image/png" } ]) ])
    post_run(data, { att_0: upload_file })
    expect(response).to have_http_status(413)
  end

  it "accepts more than 128 attachment parts" do
    attachments = Array.new(130) { |i| { "name" => "a#{i}", "part" => "att_#{i}", "content_type" => "text/plain" } }
    files = Array.new(130) { |i| [ "att_#{i}", upload_file("a#{i}.txt", "x", "text/plain") ] }.to_h
    post_run(build_payload(results: [ build_result("status" => "failed", "attachments" => attachments) ]), files)
    expect(response).to have_http_status(:created)
    expect(project.runs.sole.test_results.sole.attachments.count).to eq(130)
  end

  it "accepts a schema 2 run with a quarantined result and rejects quarantined in schema 1" do
    post_run(build_payload(schema_version: 2, results: [ build_result(status: "quarantined") ]))
    expect(response).to have_http_status(:created)
    expect(project.runs.sole).to have_attributes(schema_version: 2, quarantined_count: 1, status: "passed")

    post_run(build_payload(results: [ build_result(status: "quarantined") ]))
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["details"]).to eq([ "results[0].status must be one of passed, failed, pending, skipped" ])
    expect(project.runs.count).to eq(1)
  end
end
