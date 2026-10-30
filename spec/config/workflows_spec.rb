require "rails_helper"

RSpec.describe "GitHub workflows" do
  def workflow(name) = YAML.safe_load(Rails.root.join(".github/workflows/#{name}").read, aliases: true)

  it "runs the specs and both boot checks on every push and pull request" do
    ci = workflow("ci.yml")
    triggers = ci[true] || ci["on"]
    expect(triggers).to have_key("pull_request")
    expect(triggers.dig("push", "branches")).to eq([ "main" ])
    jobs = ci["jobs"]
    expect(jobs.keys).to include("test", "boot-source", "boot-docker", "lint", "scan_ruby", "scan_js")
    expect(jobs.dig("test", "steps").map { |s| s["run"] }.compact).to include("bundle exec rspec")
    expect(jobs.dig("boot-source", "steps").map { |s| s["run"] }.compact).to include("script/boot-check source")
    expect(jobs.dig("boot-docker", "steps").map { |s| s["run"] }.compact).to include("script/boot-check docker --keep")
  end

  it "scans for secrets, vulnerable packages and licenses" do
    jobs = workflow("ci.yml")["jobs"]
    expect(jobs.keys).to include("secrets", "osv", "licenses")
    checkout = jobs.dig("secrets", "steps").find { |s| s["uses"].to_s.start_with?("actions/checkout") }
    expect(checkout.dig("with", "fetch-depth")).to eq(0)
    expect(jobs.dig("scan_ruby", "steps").map { |s| s["run"] }.compact).to include("bundle exec ruby-audit check")
    expect(jobs.dig("licenses", "steps").map { |s| s["run"] }.compact.join).to include("license_finder")
  end

  it "gives the token read-only access and keeps event values out of shell code" do
    ci = workflow("ci.yml")
    expect(ci["permissions"]).to eq("contents" => "read")
    scan = ci.dig("jobs", "secrets", "steps").find { |s| s["run"].to_s.include?("bin/scan-secrets") }
    expect(scan["run"]).not_to include("${{")
    expect(scan["env"]).to eq("EVENT_NAME" => "${{ github.event_name }}", "BASE_REF" => "${{ github.base_ref }}")
  end

  it "removes both boot-check containers when the docker job stops" do
    stop = workflow("ci.yml").dig("jobs", "boot-docker", "steps").find { |s| s["name"] == "Stop the container" }
    expect(stop["if"]).to eq("always()")
    expect(stop["run"]).to include("docker rm -f hideout-boot-check hideout-boot-check-tls")
  end

  it "runs a pinned gitleaks image" do
    script = Rails.root.join("bin/scan-secrets").read
    expect(script).to match(%r{ghcr\.io/gitleaks/gitleaks:v\d+\.\d+\.\d+ })
    expect(script).not_to include("gitleaks:latest")
  end

  it "runs a ZAP baseline against the booted container without opening issues" do
    steps = workflow("ci.yml").dig("jobs", "boot-docker", "steps")
    expect(steps.map { |s| s["run"] }.compact).to include("script/boot-check docker --keep")
    zap = steps.find { |s| s["uses"].to_s.start_with?("zaproxy/action-baseline") }
    expect(zap["with"]).to include("target" => "http://localhost:3010", "rules_file_name" => ".zap/rules.tsv",
                                   "allow_issue_writing" => false, "fail_action" => true)
  end

  it "publishes a multi-arch image to GHCR on version tags" do
    release = workflow("release.yml")
    expect(release.dig(true, "push", "tags") || release.dig("on", "push", "tags")).to eq([ "v*" ])
    expect(release["permissions"]).to include("packages" => "write")
    steps = release.dig("jobs", "image", "steps")
    build = steps.find { |s| s["uses"].to_s.start_with?("docker/build-push-action") }
    expect(build.dig("with", "platforms")).to eq("linux/amd64,linux/arm64")
    meta = steps.find { |s| s["uses"].to_s.start_with?("docker/metadata-action") }
    expect(meta.dig("with", "images")).to eq("ghcr.io/raiderhq/hideout")
    # latest only for releases, not pre-releases (v1.0.0-rc.1)
    expect(meta.dig("with", "flavor")).to eq("latest=auto")
    expect(meta.dig("with", "tags").lines.map(&:strip)).to eq([ "type=semver,pattern={{version}}" ])
  end

  it "ships an executable boot-check script" do
    expect(File.executable?(Rails.root.join("script/boot-check"))).to be(true)
  end
end
