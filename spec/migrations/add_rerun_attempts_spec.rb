require "rails_helper"
require Rails.root.join("db/migrate/20261102120000_add_rerun_attempts").to_s

RSpec.describe "re-run attempts backfill" do
  it "keys attempt-1 GitHub builds, leaves attempt 2 and Azure NULL, and marks gate-evaluated builds" do
    github = create(:build, provider: "github_actions", attempt: "1", build_key: "github_actions:acme/shop:42:1")
    rerun = create(:build, provider: "github_actions", attempt: "2", build_key: "github_actions:acme/shop:43:2")
    azure = create(:build, provider: "azure_pipelines", attempt: "1", build_key: "azure_pipelines:x/y/z:9:1")
    synthetic = create(:build, provider: "github_actions", attempt: nil, build_key: "run:abc")
    null_attempt_one = create(:build, provider: "github_actions", attempt: nil, build_key: "github_actions:acme/shop:44:1")
    null_attempt_two = create(:build, provider: "github_actions", attempt: nil, build_key: "github_actions:acme/shop:44:2")
    padded = create(:build, provider: "github_actions", attempt: nil, build_key: "github_actions:acme/shop:42:01")
    huge = create(:build, provider: "github_actions", attempt: nil, build_key: "github_actions:acme/shop:42:99999999999")
    evaluated = create(:build)
    evaluated.update_columns(gate_status: "failed", gate_evaluated_at: 1.hour.ago)

    expect { AddRerunAttempts::Backfill.call }.not_to raise_error

    expect(github.reload.ci_run_key).to eq("github_actions:acme/shop:42")
    expect(null_attempt_one.reload.ci_run_key).to eq("github_actions:acme/shop:44")
    expect(null_attempt_two.reload.ci_run_key).to be_nil
    expect(padded.reload.ci_run_key).to be_nil
    expect(huge.reload.ci_run_key).to be_nil
    expect(rerun.reload.ci_run_key).to be_nil
    expect(azure.reload.ci_run_key).to be_nil
    expect(synthetic.reload.ci_run_key).to be_nil
    expect(evaluated.reload.gate_attempt).to eq(1)
    expect(github.reload.gate_attempt).to be_nil
  end
end
