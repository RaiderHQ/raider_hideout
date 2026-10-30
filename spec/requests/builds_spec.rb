require "rails_helper"

RSpec.describe "Builds", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }

  before { sign_in(user) }

  it "subscribes project pages through the membership-checked channel" do
    [ project_path(project), project_builds_path(project), project_runs_path(project) ].each do |path|
      get path
      sources = Nokogiri::HTML(response.body).css("turbo-cable-stream-source")
      expect(sources).not_to be_empty, path
      expect(sources.map { |s| s["channel"] }.uniq).to eq([ "ProjectStreamsChannel" ]), path
    end
  end

  it "lists builds newest first with a branch filter" do
    create(:build, project: project, branch: "main", commit_message: "Old main")
    create(:build, project: project, branch: "feature", commit_message: "Feature work")
    get project_builds_path(project)
    expect(response.body.index("Feature work")).to be < response.body.index("Old main")
    get project_builds_path(project, branch: "main")
    expect(response.body).to include("Old main")
    expect(response.body).not_to include("Feature work")
  end

  it "shows status, sha, shard progress, counts and duration in the row" do
    create(:build, project: project, status: "incomplete", commit_sha: "abcdef1234567", expected_shards: 4,
                   passed_count: 7, failed_count: 2, duration_ms: 12_500).tap { |b| create_list(:run, 2, project: project, build: b) }
    get project_builds_path(project)
    expect(response.body).to include("incomplete", "abcdef1", "12.5s", "2/4")
    expect(response.body).not_to include("abcdef12")
  end

  it "keeps the builds index query count constant (no N+1)" do
    count_queries = lambda do
      n = 0
      sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |*, p| n += 1 unless p[:name] == "SCHEMA" || p[:sql] =~ /\A\s*(BEGIN|COMMIT|SAVEPOINT|RELEASE)/ }
      get project_builds_path(project)
      ActiveSupport::Notifications.unsubscribe(sub)
      n
    end
    create(:build, project: project, expected_shards: 2).tap { |b| create_list(:run, 2, project: project, build: b) }
    baseline = count_queries.call
    4.times { create(:build, project: project, expected_shards: 2).tap { |b| create_list(:run, 2, project: project, build: b) } }
    expect(count_queries.call).to eq(baseline)
    expect(baseline).to be <= 10
  end

  it "404s for another user's project" do
    get project_builds_path(create(:project))
    expect(response).to have_http_status(:not_found)
  end

  it "shows the empty state when there are no builds" do
    get project_builds_path(project)
    expect(response.body).to include("No builds yet")
  end

  it "links Builds from the project page" do
    get project_path(project)
    expect(response.body).to include(project_builds_path(project))
  end

  describe "PR chip on builds list" do
    it "shows a PR chip with link when pr_number and valid repository are present" do
      create(:build, project: project, pr_number: 42, provider: "github_actions", repository: "RaiderHQ/demo")
      get project_builds_path(project)
      expect(response.body).to include("PR #42")
      expect(response.body).to include("https://github.com/RaiderHQ/demo/pull/42")
      expect(response.body).to include('rel="noopener noreferrer"')
      expect(response.body).to include('target="_blank"')
    end

    it "does not render nested links in build rows" do
      create(:build, project: project, pr_number: 42, provider: "github_actions", repository: "RaiderHQ/demo")
      get project_builds_path(project)

      # Nokogiri repairs nested <a> while parsing, so scan the raw HTML.
      # Anchors never nest anywhere on the page, so every row is covered.
      expect(response.body).to include("PR #42")
      depth = 0
      max_depth = response.body.scan(%r{<a\b|</a>}i).map { |tag| depth += tag.start_with?("</") ? -1 : 1 }.max
      expect(max_depth).to eq(1), "Found nested <a> tags (max depth: #{max_depth})"
    end

    it "does not show a PR chip when pr_number is missing" do
      create(:build, project: project, pr_number: nil, repository: "RaiderHQ/demo")
      get project_builds_path(project)
      expect(response.body).not_to include("PR #")
    end

    it "does not show a PR chip when repository is missing" do
      create(:build, project: project, pr_number: 42, repository: nil)
      get project_builds_path(project)
      expect(response.body).not_to include("PR #")
    end

    it "does not show a PR chip when repository format is invalid" do
      create(:build, project: project, pr_number: 42, repository: "invalid-format")
      get project_builds_path(project)
      expect(response.body).not_to include("PR #")
      expect(response.body).not_to include("https://github.com")
    end
  end

  describe "PR chip on builds show page" do
    it "shows a PR chip with link in the header when pr_number and valid repository are present" do
      build = create(:build, project: project, pr_number: 99, provider: "github_actions", repository: "RaiderHQ/demo")
      get project_build_path(project, build)
      expect(response.body).to include("PR #99")
      expect(response.body).to include("https://github.com/RaiderHQ/demo/pull/99")
      expect(response.body).to include('rel="noopener noreferrer"')
      expect(response.body).to include('target="_blank"')
    end

    it "does not show a PR chip when pr_number is missing" do
      build = create(:build, project: project, pr_number: nil, repository: "RaiderHQ/demo")
      get project_build_path(project, build)
      expect(response.body).not_to include("PR #")
    end

    it "does not show a PR chip when repository is missing" do
      build = create(:build, project: project, pr_number: 42, repository: nil)
      get project_build_path(project, build)
      expect(response.body).not_to include("PR #")
    end

    it "does not show a PR chip when repository format is invalid" do
      build = create(:build, project: project, pr_number: 42, repository: "invalid/format/extra")
      get project_build_path(project, build)
      expect(response.body).not_to include("PR #")
      expect(response.body).not_to include("https://github.com")
    end

    it "does not render the PR wrapper div when pr_number is nil" do
      build = create(:build, project: project, pr_number: nil, repository: "RaiderHQ/demo")
      get project_build_path(project, build)
      doc = Nokogiri::HTML(response.body)
      pr_wrapper = doc.at('[data-testid="pr-chips"]')
      expect(pr_wrapper).to be_nil, "PR wrapper div should not be rendered when pr_number is nil"
    end
  end

  describe "pagination" do
    before { create_list(:build, 26, project: project, branch: "main") }

    it "renders a nav on page 1 linking to page 2, without inline styles or handlers" do
      get project_builds_path(project, branch: "main")
      nav = Nokogiri::HTML(response.body).at_css("nav.pagy")
      expect(nav).not_to be_nil
      expect(nav.at_css("a[aria-current='page']").text).to eq("1")
      expect(nav.at_css("a[rel='next']")["href"]).to include("page=2").and include("branch=main")
      expect(nav.to_html).not_to match(/\sstyle=|\sonclick=/)
    end

    it "serves page 2 with the remaining build and marks it current" do
      get project_builds_path(project, branch: "main", page: 2)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("nav.pagy a[aria-current='page']").text).to eq("2")
      expect(doc.at_css("nav.pagy a[rel='prev']")["href"]).to include("page=1")
    end
  end
end
