require "rails_helper"

RSpec.describe Push::Payload do
  let(:project) { create(:project, name: "Checkout") }
  let(:build) { create(:build, project: project, branch: "main", status: "failed", failed_count: 2) }

  it "names the project, branch, failure count and first failed test, and links to its card" do
    result = add_failed_result(build)
    payload = described_class.for(build, %w[failed])
    expect(payload).to eq(
      title: "Raider: build failed — Checkout",
      body: "main · 2 failed\nCheckout fails",
      path: "/projects/#{project.to_param}/builds/#{build.to_param}?result=#{result.id}#test_result_#{result.id}"
    )
    expect(payload[:path]).to include("result=#{result.id}").and include("#test_result_")
  end

  it "falls back to the build page when nothing failed" do
    payload = described_class.for(build, %w[failed])
    expect(payload[:path]).to eq(Rails.application.routes.url_helpers.project_build_path(project, build))
    expect(payload[:body]).to eq("main · 2 failed")
  end

  it "prefixes re-runs" do
    build.update!(ci_run_key: "gha:1")
    allow(build).to receive(:rerun_attempt?).with(2).and_return(true)
    expect(described_class.for(build, %w[failed], attempt: 2)[:title]).to eq("Raider: Re-run (attempt 2): build failed — Checkout")
  end

  it "titles gate and flaky pushes by their event" do
    expect(described_class.for(build, %w[gate_failed])[:title]).to eq("Raider: quality gate failed — Checkout")
    expect(described_class.for(build, %w[new_flaky])[:title]).to eq("Raider: new flaky tests — Checkout")
  end

  it "stays under 3,000 bytes with a huge test name, branch and multibyte text" do
    build.update!(branch: "é" * 400)
    add_failed_result(build, name: "日本語" * 2_000)
    expect(described_class.for(build, %w[failed]).to_json.bytesize).to be < 3_000
    add_failed_result(build, name: "x" * 5_000)
    expect(described_class.for(build, %w[failed]).to_json.bytesize).to be < 3_000
  end
end
