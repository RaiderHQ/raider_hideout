module Analytics
  # The current flaky verdicts on the branch (spec 2026-10-28 §4.4, list 3), narrowed by file:
  # and, when tag: is set, to tests with a result in the window carrying the tags.
  class FlakyRanking < Query
    ORDER = "COALESCE(test_case_verdicts.flip_rate, 0) DESC, test_cases.full_name ASC, test_cases.id ASC".freeze

    Row = Struct.new(:test_case, :flip_rate, :reason, :flaky_since_build, :sample_count, :quarantined, keyword_init: true)

    def rows(limit:)
      verdicts = scope.order(Arel.sql(ORDER)).limit(limit).includes(:test_case, :flaky_since_build).to_a
      quarantined = Quarantine.active(@now).where(project_id: @project.id, test_case_id: verdicts.map(&:test_case_id))
                              .pluck(:test_case_id).to_set
      verdicts.map do |verdict|
        Row.new(test_case: verdict.test_case, flip_rate: verdict.flip_rate && (verdict.flip_rate * 100).round, reason: verdict.flaky_reason,
                flaky_since_build: verdict.flaky_since_build, sample_count: verdict.sample_count,
                quarantined: quarantined.include?(verdict.test_case_id))
      end
    end

    private

    def scope
      verdicts = TestCaseVerdict.joins(:test_case).where(test_cases: { project_id: @project.id }, branch: branch, flaky: true)
      verdicts = contains(verdicts, %w[test_cases.file_path], @filter.file) if @filter.file
      verdicts = verdicts.where(test_case_id: results.select(:test_case_id)) if @filter.tags.any?
      verdicts
    end
  end
end
