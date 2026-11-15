require "rails_helper"

RSpec.describe RunRequest do
  include ActiveSupport::Testing::TimeHelpers

  let(:project) { create(:project) }
  let(:user) { create(:user, email_address: "ana@example.com") }

  def request_for(**attrs)
    described_class.create!({ project: project, user: user, ref: "main", repository: "acme/shop-tests",
                              workflow: "test_pipeline.yml", status: "accepted" }.merge(attrs))
  end

  describe "#build" do
    it "finds the GitHub Actions build with the run id in the same project only" do
      other = create(:build, project: create(:project), provider: "github_actions", build_id: "123")
      request = request_for(github_run_id: "123")
      expect(request.build).to be_nil
      create(:build, project: project, provider: "azure", build_id: "123")
      expect(described_class.find(request.id).build).to be_nil
      mine = create(:build, project: project, provider: "github_actions", build_id: "123",
                            ci_run_key: "github_actions:Acme/Shop-Tests:123")
      expect(described_class.find(request.id).build).to eq(mine)
      expect(other.build_id).to eq(mine.build_id)
    end

    it "is nil without a run id" do
      create(:build, project: project, provider: "github_actions", build_id: nil)
      expect(request_for(github_run_id: nil).build).to be_nil
    end
  end

  describe "#state_copy" do
    it "covers every panel state" do
      travel_to(Time.zone.parse("2026-11-15 12:00:00")) do
        expect(request_for(status: "pending").state_copy).to eq("waiting for GitHub")
        expect(request_for(status: "pending", created_at: 11.minutes.ago).state_copy).to eq("no answer recorded")
        expect(request_for(github_run_id: "5").state_copy).to eq("waiting for results")
        expect(request_for(github_run_id: "5", created_at: 121.minutes.ago).state_copy).to eq("no results yet")
        expect(request_for(github_run_id: nil).state_copy).to eq("started on GitHub")
        build = create(:build, project: project, provider: "github_actions", build_id: "7")
        expect(request_for(github_run_id: "7", created_at: 3.hours.ago).state_copy).to eq("Build ##{build.id}")
        expect(request_for(status: "rejected", http_status: 401).state_copy).to eq("GitHub rejected the token. Replace it in CI access.")
        expect(request_for(status: "rejected", http_status: 422, message: "No ref found for: x").state_copy)
          .to eq("GitHub refused the run: No ref found for: x")
        expect(request_for(status: "failed", http_status: nil).state_copy).to eq("Couldn't reach GitHub.")
      end
    end
  end

  it "links to the run, or to the workflow when there is no run id" do
    expect(request_for(github_run_id: "5", html_url: "https://github.com/Acme/shop-tests/actions/runs/5").github_url)
      .to eq("https://github.com/Acme/shop-tests/actions/runs/5")
    expect(request_for(github_run_id: "5").github_url).to eq("https://github.com/acme/shop-tests/actions/runs/5")
    expect(request_for.github_url).to eq("https://github.com/acme/shop-tests/actions/workflows/test_pipeline.yml")
  end

  it "labels the request" do
    request = request_for(tags: "@smoke")
    expect([ request.tags_label, request.requester_label ]).to eq([ "Tags: @smoke", "ana@example.com" ])
    expect(request_for.tags_label).to eq("All tests")
    expect(request_for(user: nil).requester_label).to eq("someone")
  end

  it "lists the last 24 hours, newest first, at most 5" do
    travel_to(Time.zone.parse("2026-11-15 12:00:00")) do
      request_for(ref: "old", created_at: 25.hours.ago)
      refs = 6.times.map { |i| request_for(ref: "r#{i}", created_at: (10 - i).minutes.ago).ref }
      request_for(ref: "elsewhere", project: create(:project))
      expect(described_class.recent(project).map(&:ref)).to eq(refs.last(5).reverse)
    end
  end

  it "keeps the row when its user is deleted, and goes with its project" do
    request = request_for
    user.destroy
    expect(request.reload.user_id).to be_nil
    project.destroy
    expect(described_class.exists?(request.id)).to be(false)
  end

  it "accepts the tags the generated workflow accepts, and nothing else" do
    [ "@smoke", "smoke", "~slow", "!slow", "@smoke, @fast", "smoke fast", "type:api", "@type::api", "a.b-c_d" ].each do |tags|
      expect(described_class.valid_tags?(tags)).to be(true), tags.inspect
    end
    [ "a:", "a:b:c", "@@x", "~~x", "x!", "-x", ".x", ", ,", " ", "", "a\"b", "a\nb", "x" * 201, nil ].each do |tags|
      expect(described_class.valid_tags?(tags)).to be(false), tags.inspect
    end
  end
end
