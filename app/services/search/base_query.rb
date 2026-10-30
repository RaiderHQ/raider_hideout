module Search
  # Range and matching rules shared by both levels (spec §4.2–4.3). Every query is one
  # project's results on one branch since the filter's range start.
  class BaseQuery
    PER_PAGE = 50

    def initialize(project, filter, now: Time.current)
      @project = project
      @filter = filter
      @now = now
    end

    def branch = @filter.branch || @project.default_branch

    private

    def in_range
      TestResult.joins(:run, :test_case)
                .where(runs: { project_id: @project.id, branch: branch, created_at: @filter.range_start(@now).. })
    end

    # Case-insensitive substring match on any of the columns, wildcards escaped.
    def contains(scope, columns, value)
      pattern = "%#{Like.escape(value.downcase(:ascii))}%"
      matches = columns.map do |column|
        table, name = column.split(".")
        Arel::Table.new(table)[name].lower.matches(pattern, "\\")
      end
      scope.where(matches.reduce(:or))
    end

    def with_tags(scope)
      @filter.tags.reduce(scope) do |acc, tag|
        acc.where("test_results.tags_text LIKE ? ESCAPE '\\'", "%|#{Like.escape(tag)}|%")
      end
    end

    def flaky_case_ids = TestCaseVerdict.where(branch: branch, flaky: true).select(:test_case_id)

    def quarantined_case_ids = Quarantine.active(@now).where(project_id: @project.id).select(:test_case_id)

    # SQLite returns aggregate timestamps as strings.
    def parse_time(value) = value.is_a?(String) ? Time.zone.parse("#{value} UTC") : value
  end
end
