module Analytics
  # Executed results grouped by spec file (spec 2026-10-28 §4.4, list 4; D2: suite = file).
  class FileRanking < Query
    ORDER = "#{FAILED} DESC, #{RATE} DESC, test_cases.file_path ASC".freeze

    Row = Struct.new(:file_path, :tests, :executed, :failures, :failure_rate, :total_duration_ms, keyword_init: true)

    def rows(limit:)
      executed.group("test_cases.file_path").order(Arel.sql(ORDER)).limit(limit)
              .pluck("test_cases.file_path", Arel.sql("COUNT(DISTINCT test_results.test_case_id)"), Arel.sql("COUNT(*)"),
                     Arel.sql(FAILED), Arel.sql("SUM(test_results.duration_ms)"))
              .map do |file, tests, count, failures, sum|
                Row.new(file_path: file, tests: tests.to_i, executed: count.to_i, failures: failures.to_i,
                        failure_rate: self.class.floored_rate(failures.to_i, count.to_i), total_duration_ms: sum.to_i)
              end
    end
  end
end
