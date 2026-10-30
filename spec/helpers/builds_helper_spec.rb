require "rails_helper"

RSpec.describe BuildsHelper, type: :helper do
  let(:project) { create(:project) }

  describe "#pull_request_url" do
    it "returns nil when pr_number is not present" do
      build = create(:build, project: project, pr_number: nil, repository: "RaiderHQ/demo")
      expect(helper.pull_request_url(build)).to be_nil
    end

    it "returns nil when repository is not present" do
      build = create(:build, project: project, pr_number: 42, repository: nil)
      expect(helper.pull_request_url(build)).to be_nil
    end

    it "returns nil when repository format is invalid" do
      build = create(:build, project: project, pr_number: 42, repository: "invalid")
      expect(helper.pull_request_url(build)).to be_nil
    end

    it "returns nil when repository has invalid characters" do
      build = create(:build, project: project, pr_number: 42, repository: "RaiderHQ/demo/extra")
      expect(helper.pull_request_url(build)).to be_nil
    end

    it "returns the GitHub PR URL when both pr_number and valid repository are present" do
      build = create(:build, project: project, provider: "github_actions", pr_number: 42, repository: "RaiderHQ/demo")
      expect(helper.pull_request_url(build)).to eq("https://github.com/RaiderHQ/demo/pull/42")
    end

    it "handles repositories with hyphens and dots in the names" do
      build = create(:build, project: project, provider: "github_actions", pr_number: 99, repository: "raider-hq/demo.test")
      expect(helper.pull_request_url(build)).to eq("https://github.com/raider-hq/demo.test/pull/99")
    end

    it "handles repositories with underscores in the names" do
      build = create(:build, project: project, provider: "github_actions", pr_number: 1, repository: "raider_hq/demo_test")
      expect(helper.pull_request_url(build)).to eq("https://github.com/raider_hq/demo_test/pull/1")
    end

    it "rejects owner segment made only of dots" do
      build = create(:build, project: project, pr_number: 42, repository: "../demo")
      expect(helper.pull_request_url(build)).to be_nil
    end

    it "rejects repo segment made only of dots" do
      build = create(:build, project: project, pr_number: 42, repository: "owner/..")
      expect(helper.pull_request_url(build)).to be_nil
    end

    it "rejects both segments made only of dots" do
      build = create(:build, project: project, pr_number: 42, repository: "../..")
      expect(helper.pull_request_url(build)).to be_nil
    end

    it "rejects dot-slash segments" do
      build = create(:build, project: project, pr_number: 42, repository: "./owner")
      expect(helper.pull_request_url(build)).to be_nil
    end

    it "rejects repository with trailing newline" do
      build = create(:build, project: project, pr_number: 42, repository: "owner/repo\n")
      expect(helper.pull_request_url(build)).to be_nil
    end
  end

  describe "#pull_request_url with pr_url / provider" do
    it "returns pr_url when present" do
      build = create(:build, project: project, provider: "azure_pipelines", pr_url: "https://dev.azure.com/o/P/_git/r/pullrequest/7")
      expect(helper.pull_request_url(build)).to eq("https://dev.azure.com/o/P/_git/r/pullrequest/7")
    end

    it "falls back to the GitHub URL for github_actions without pr_url" do
      build = create(:build, project: project, provider: "github_actions", repository: "o/r", pr_number: 5)
      expect(helper.pull_request_url(build)).to eq("https://github.com/o/r/pull/5")
    end

    it "returns nil for azure_pipelines without pr_url" do
      build = create(:build, project: project, provider: "azure_pipelines", repository: "Raider/demo", pr_number: 5)
      expect(helper.pull_request_url(build)).to be_nil
    end
  end

  describe "#ci_provider_label" do
    it "labels known providers, passes others through, defaults to CI" do
      expect(helper.ci_provider_label(build_stubbed(:build, provider: "github_actions"))).to eq("GitHub Actions")
      expect(helper.ci_provider_label(build_stubbed(:build, provider: "azure_pipelines"))).to eq("Azure Pipelines")
      expect(helper.ci_provider_label(build_stubbed(:build, provider: "jenkins"))).to eq("jenkins")
      expect(helper.ci_provider_label(build_stubbed(:build, provider: nil))).to eq("CI")
    end
  end
end
