module Search
  # One row per test that ran on the branch in range (spec §4.2). Status and tags
  # describe the test now, so they are checked on its latest result in range.
  class TestsQuery < BaseQuery
    Row = Struct.new(:test_case, :latest_status, :pass_rate, :failures, :avg_duration_ms, :last_run_at, :flaky, keyword_init: true)

    PASSED = "SUM(CASE WHEN test_results.status = 'passed' THEN 1 ELSE 0 END)".freeze
    # Quarantined results count as failures (spec §5.1), so a quarantined test never looks healthy.
    FAILED = "SUM(CASE WHEN test_results.status IN (#{TestResult::FAILING_STATUSES.map { "'#{_1}'" }.join(', ')}) THEN 1 ELSE 0 END)".freeze
    ORDERS = {
      "failures" => "#{FAILED} DESC, MIN(test_cases.full_name) ASC",
      "recent" => "MAX(runs.created_at) DESC",
      "duration" => "AVG(test_results.duration_ms) DESC",
      "name" => "MIN(test_cases.full_name) ASC"
    }.freeze

    def count = scope.distinct.count(:test_case_id)

    def page(limit:, offset:) = rows(scope, limit: limit, offset: offset)

    # One test's row over the same branch and range (the API's test detail), or nil when it did not run there.
    def row_for(test_case) = rows(scope.where(test_case_id: test_case.id), limit: 1, offset: 0).first

    private

    def rows(relation, limit:, offset:)
      order = Arel.sql("#{ORDERS.fetch(@filter.sort_for('tests'))}, test_results.test_case_id ASC")
      stats = relation.group("test_results.test_case_id").order(order).limit(limit).offset(offset)
                      .pluck("test_results.test_case_id", Arel.sql("MAX(test_results.id)"), Arel.sql(PASSED), Arel.sql(FAILED),
                             Arel.sql("AVG(test_results.duration_ms)"), Arel.sql("MAX(runs.created_at)"))
      cases = @project.test_cases.where(id: stats.map(&:first)).index_by(&:id)
      statuses = TestResult.where(id: stats.map(&:second)).pluck(:id, :status).to_h
      flaky = TestCaseVerdict.where(test_case_id: cases.keys, branch: branch, flaky: true).pluck(:test_case_id).to_set
      stats.map do |id, latest_id, passed, failed, avg, last|
        decided = passed.to_i + failed.to_i
        Row.new(test_case: cases.fetch(id), latest_status: statuses[latest_id], failures: failed.to_i,
                pass_rate: decided.positive? ? (100.0 * passed.to_i / decided).round : nil,
                avg_duration_ms: avg.to_f.round, last_run_at: parse_time(last), flaky: flaky.include?(id))
      end
    end

    def scope
      @scope ||= begin
        s = in_range
        s = @filter.text.reduce(s) { |acc, word| contains(acc, %w[test_cases.full_name test_cases.file_path], word) }
        s = contains(s, %w[test_cases.full_name], @filter.name) if @filter.name
        s = contains(s, %w[test_cases.file_path], @filter.file) if @filter.file
        s = s.where(test_case_id: flaky_case_ids) if @filter.flaky
        s = s.where(test_case_id: quarantined_case_ids) if @filter.quarantined
        s = s.where(test_case_id: error_case_ids) if @filter.error
        s = s.where(test_case_id: latest_matching(s)) if @filter.statuses.any? || @filter.tags.any?
        s
      end
    end

    def error_case_ids
      failed = in_range.where(status: TestResult::FAILING_STATUSES)
      contains(failed, %w[test_results.failure_message test_results.exception_class], @filter.error).select(:test_case_id)
    end

    def latest_matching(scope)
      latest = TestResult.where(id: scope.group("test_results.test_case_id").select("MAX(test_results.id)"))
      latest = latest.where(status: @filter.statuses) if @filter.statuses.any?
      with_tags(latest).select(:test_case_id)
    end
  end
end
