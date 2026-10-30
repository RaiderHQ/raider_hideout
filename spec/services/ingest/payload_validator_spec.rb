require "rails_helper"

RSpec.describe Ingest::PayloadValidator do
  def errors(data, parts = [])
    described_class.new(data, parts).errors
  end

  it "accepts a valid payload" do
    expect(errors(build_payload)).to eq([])
  end

  it "rejects non-objects and unknown schema versions" do
    expect(errors([])).to eq([ "payload must be a JSON object" ])
    expect(errors(build_payload(schema_version: 3))).to eq([ "unsupported schema_version 3; supported: 1, 2" ])
  end

  it "requires client_run_id, run object and results array" do
    expect(errors(build_payload(client_run_id: "", run: "x", results: {})))
      .to include("client_run_id is required", "run must be an object", "results must be an array")
  end

  it "rejects unparsable timestamps" do
    data = build_payload
    data["run"]["started_at"] = "yesterday-ish"
    expect(errors(data)).to include("run.started_at is not an ISO 8601 time")
  end

  it "checks each result" do
    data = build_payload(results: [ build_result(status: "exploded", full_name: "", tags: "smoke"), 5 ])
    expect(errors(data)).to include(
      "results[0].full_name is required",
      "results[0].status must be one of passed, failed, pending, skipped",
      "results[0].tags must be an array of strings",
      "results[1] must be an object"
    )
  end

  it "requires every referenced part to be uploaded" do
    data = build_payload(results: [ build_result(attachments: [ { "name" => "s", "part" => "att_0", "content_type" => "image/png" } ]) ])
    expect(errors(data, [])).to include('results[0].attachments[0].part "att_0" was not uploaded')
    expect(errors(data, [ "att_0" ])).to eq([])
  end

  it "accepts a run without ci, git or environment and non-string environment values" do
    data = build_payload
    data["run"] = { "started_at" => "2026-10-10T12:00:00Z", "environment" => { "ruby" => "4.0.2", "headless" => true } }
    expect(errors(data)).to eq([])
    data["run"] = {}
    expect(errors(data)).to eq([])
  end

  it "requires duration_ms, attempts and line_number to be in-range integers" do
    data = build_payload(results: [
      build_result(duration_ms: [ 1 ], attempts: true, line_number: "abc"),
      build_result(duration_ms: 1.5, attempts: 2**70, line_number: -1)
    ])
    expect(errors(data)).to include(
      "results[0].duration_ms must be an integer", "results[0].attempts must be an integer",
      "results[0].line_number must be an integer", "results[1].duration_ms must be an integer",
      "results[1].attempts is out of range", "results[1].line_number is out of range"
    )
    expect(errors(build_payload(results: [ build_result(duration_ms: nil, attempts: nil, line_number: nil) ]))).to eq([])
  end

  it "requires failure to be an object" do
    expect(errors(build_payload(results: [ build_result(failure: [ "x" ]) ]))).to include("results[0].failure must be an object")
  end

  it "requires ci and git values to be strings" do
    data = build_payload
    data["run"]["git"]["branch"] = { "a" => 1 }
    data["run"]["ci"]["build_id"] = 7
    expect(errors(data)).to include("run.git.branch must be a string", "run.ci.build_id must be a string")
  end
  it "accepts optional ci attempt, job, build_key and a shard" do
    data = build_payload
    data["run"]["ci"].merge!("attempt" => "2", "job" => "test", "build_key" => "github_actions:acme/app:1:2")
    data["run"]["shard"] = { "index" => 1, "total" => 2, "label" => "test#1" }
    expect(errors(data)).to eq([])
    data["run"]["shard"] = { "index" => 3, "total" => nil, "label" => "test#1.3" }
    expect(errors(data)).to eq([])
    data["run"]["shard"] = nil
    expect(errors(data)).to eq([])
  end

  it "requires ci attempt, job and build_key to be strings and build_key to fit" do
    data = build_payload
    data["run"]["ci"].merge!("attempt" => 2, "job" => [ "x" ], "build_key" => 7)
    expect(errors(data)).to include("run.ci.attempt must be a string", "run.ci.job must be a string",
                                    "run.ci.build_key must be a string")
    data["run"]["ci"]["build_key"] = "k" * 256
    expect(errors(data)).to include("run.ci.build_key is too long (maximum 255 characters)")
  end

  it "validates the shard object" do
    data = build_payload
    data["run"]["shard"] = "1"
    expect(errors(data)).to eq([ "run.shard must be an object" ])
    data["run"]["shard"] = { "index" => 0, "total" => 0, "label" => 5 }
    expect(errors(data)).to include("run.shard.index is out of range", "run.shard.total is out of range",
                                    "run.shard.label must be a string")
    data["run"]["shard"] = { "index" => "1", "total" => 1.5, "label" => "x" * 256 }
    expect(errors(data)).to include("run.shard.index must be an integer", "run.shard.total must be an integer",
                                    "run.shard.label is too long (maximum 255 characters)")
    data["run"]["shard"] = { "total" => 2**31, "label" => "x" }
    expect(errors(data)).to include("run.shard.index must be an integer", "run.shard.total is out of range")
    data["run"]["shard"] = { "index" => 1 }
    expect(errors(data)).to include("run.shard.label must be a string")
  end

  describe "pull request fields" do
    let(:pr) { { "number" => 7, "base_branch" => "main", "head_branch" => "feat", "head_sha" => "abc" } }

    def payload_with(ci: {}, git: {})
      build_payload.tap do |d|
        d["run"]["ci"].merge!(ci)
        d["run"]["git"].merge!(git)
      end
    end

    it "accepts repository, default_branch and a valid pr" do
      expect(errors(payload_with(ci: { "repository" => "a/b" }, git: { "default_branch" => "main", "pr" => pr }))).to eq([])
    end

    it "accepts payloads without them" do
      expect(errors(build_payload)).to eq([])
    end

    it "requires repository and default_branch to be strings" do
      expect(errors(payload_with(ci: { "repository" => 5 }, git: { "default_branch" => [] })))
        .to include("run.ci.repository must be a string", "run.git.default_branch must be a string")
    end

    it "requires pr to be an object" do
      expect(errors(payload_with(git: { "pr" => "7" }))).to eq([ "run.git.pr must be an object" ])
    end

    it "treats a null pr as absent" do
      expect(errors(payload_with(git: { "pr" => nil }))).to eq([])
    end

    it "validates pr members" do
      bad = { "number" => 0, "base_branch" => 1, "head_branch" => nil }
      expect(errors(payload_with(git: { "pr" => bad }))).to include(
        "run.git.pr.number is out of range", "run.git.pr.base_branch must be a string",
        "run.git.pr.head_branch must be a string", "run.git.pr.head_sha must be a string"
      )
      expect(errors(payload_with(git: { "pr" => pr.merge("number" => "7") })))
        .to eq([ "run.git.pr.number must be an integer" ])
    end
  end

  describe "pull request validation" do
    def pr_errors(pr)
      data = build_payload
      data["run"]["git"]["pr"] = pr
      errors(data)
    end

    it "rejects a pr that is an array" do
      expect(pr_errors([ 1 ])).to include("run.git.pr must be an object")
    end

    it "rejects a number above the integer maximum" do
      pr = { "number" => Ingest::PayloadValidator::MAX_INT + 1, "base_branch" => "main", "head_branch" => "f", "head_sha" => "a" }
      expect(pr_errors(pr)).to include("run.git.pr.number is out of range")
    end

    it "rejects a nil number with valid strings" do
      pr = { "number" => nil, "base_branch" => "main", "head_branch" => "f", "head_sha" => "a" }
      expect(pr_errors(pr)).to eq([ "run.git.pr.number must be an integer" ])
    end
  end

  it "accepts quarantined only in schema 2" do
    v2 = build_payload(schema_version: 2, results: [ build_result(status: "quarantined") ])
    expect(errors(v2)).to eq([])

    v1 = build_payload(schema_version: 1, results: [ build_result(status: "quarantined") ])
    expect(errors(v1)).to eq([ "results[0].status must be one of passed, failed, pending, skipped" ])

    bad_v2 = build_payload(schema_version: 2, results: [ build_result(status: "exploded") ])
    expect(errors(bad_v2)).to eq([ "results[0].status must be one of passed, failed, pending, skipped, quarantined" ])
  end
end
