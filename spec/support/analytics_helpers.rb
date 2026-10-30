module AnalyticsHelpers
  # A build at a given time; counts and durations as keywords (Build columns).
  def analytics_build(project:, at:, branch: "main", **attributes)
    create(:build, project: project, branch: branch, created_at: at, **attributes)
  end

  # One stored result in its own run of `build`, at the build's time unless `at:` is given.
  def analytics_result(build:, test_case:, status:, duration: 100, tags: [], at: build.created_at)
    run = create(:run, project: build.project, build: build, branch: build.branch, created_at: at)
    TestResult.create!(run: run, test_case: test_case, identifier: SecureRandom.hex(4), status: status, duration_ms: duration,
                       tags: tags, tags_text: TestResult.tags_text_for(tags))
  end

  def analytics_filter(query = "", project:) = Analytics::Filter.parse(query, default_branch: project.default_branch)
end

RSpec.configure { |c| c.include AnalyticsHelpers }
