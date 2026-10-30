module Analytics
  # Most failing and slowest tests over the window (spec 2026-10-28 §4.4, lists 1 and 2):
  # one GROUP BY per list over executed results.
  class TestRanking < Query
    MODES = %w[ failing slowest ].freeze
    ORDER_BY = {
      "failing" => "#{FAILED} DESC, #{RATE} DESC, MIN(test_cases.full_name) ASC, test_results.test_case_id ASC",
      "slowest" => "AVG(test_results.duration_ms) DESC, MIN(test_cases.full_name) ASC, test_results.test_case_id ASC"
    }.freeze
    LAST_FAILURE = "MAX(CASE WHEN test_results.status IN (#{TestResult::FAILING_STATUSES.map { "'#{_1}'" }.join(', ')}) " \
                   "THEN runs.created_at END)".freeze

    Row = Struct.new(:test_case, :failures, :executed, :failure_rate, :last_failure_at, :avg_duration_ms, :max_duration_ms,
                     :total_duration_ms, :flaky, :quarantined, keyword_init: true)

    def initialize(project, filter, mode:, now: Time.current)
      super(project, filter, now: now)
      @mode = MODES.include?(mode) ? mode : raise(ArgumentError, "unknown mode #{mode.inspect}")
    end

    def rows(limit:)
      relation = executed.group("test_results.test_case_id")
      relation = relation.having(Arel.sql("#{FAILED} > 0")) if @mode == "failing"
      stats = relation.order(Arel.sql(ORDER_BY.fetch(@mode))).limit(limit)
                      .pluck("test_results.test_case_id", Arel.sql(FAILED), Arel.sql("COUNT(*)"), Arel.sql(LAST_FAILURE),
                             Arel.sql("AVG(test_results.duration_ms)"), Arel.sql("MAX(test_results.duration_ms)"),
                             Arel.sql("SUM(test_results.duration_ms)"))
      ids = stats.map(&:first)
      cases = @project.test_cases.where(id: ids).index_by(&:id)
      flaky = TestCaseVerdict.where(test_case_id: ids, branch: branch, flaky: true).pluck(:test_case_id).to_set
      quarantined = Quarantine.active(@now).where(project_id: @project.id, test_case_id: ids).pluck(:test_case_id).to_set
      stats.map do |id, failures, count, last_failure, avg, max, sum|
        Row.new(test_case: cases.fetch(id), failures: failures.to_i, executed: count.to_i,
                failure_rate: self.class.floored_rate(failures.to_i, count.to_i), last_failure_at: parse_time(last_failure),
                avg_duration_ms: avg.to_f.round, max_duration_ms: max.to_i, total_duration_ms: sum.to_i,
                flaky: flaky.include?(id), quarantined: quarantined.include?(id))
      end
    end
  end
end
