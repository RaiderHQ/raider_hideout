module Analytics
  # Results of one project on the filter's branch since its range start, narrowed by file:
  # and tag: (spec 2026-10-28 §5). Built on Search::BaseQuery so the window, branch default,
  # LIKE escaping and timestamp parsing are Explore's own.
  class Query < Search::BaseQuery
    # "Executed" (spec §4.4): skipped and pending results never count.
    EXECUTED = %w[ passed failed quarantined ].freeze
    FAILED = Search::TestsQuery::FAILED
    # Exact failures ÷ executed for ordering; the page shows it floored.
    RATE = "#{FAILED} * 1.0 / COUNT(*)".freeze

    def initialize(project, filter, now: Time.current)
      super(project, filter.search, now: now)
    end

    def self.floored_rate(failures, executed) = executed.positive? ? failures * 100 / executed : nil

    # Whether the window holds any executed result (after file: and tag:).
    def any_executed? = executed.exists?

    private

    def results
      scope = in_range
      scope = contains(scope, %w[ test_cases.file_path ], @filter.file) if @filter.file
      with_tags(scope)
    end

    def executed = results.where(status: EXECUTED)
  end
end
