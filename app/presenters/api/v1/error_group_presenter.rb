module Api
  module V1
    # §5.7 error group and §5.8 detail.
    class ErrorGroupPresenter < BasePresenter
      TESTS_LIMIT = 50

      def initialize(group, url_options:)
        super(url_options: url_options)
        @group = group
      end

      def to_h(affected_tests:)
        { id: @group.id, exception_class: @group.exception_class, sample_message: clip(@group.sample_message, ProjectPresenter::SAMPLE_MESSAGE_LIMIT),
          frame: @group.frame, first_seen_at: time(@group.first_seen_at), last_seen_at: time(@group.last_seen_at),
          affected_tests: affected_tests }
      end

      def detail(affected_tests:)
        to_h(affected_tests: affected_tests).merge(tests: tests)
      end

      private

      # Most recently failed first.
      def tests
        rows = @group.test_results.where(status: TestResult::FAILING_STATUSES).joins(:run).group(:test_case_id)
                     .order(Arel.sql("MAX(runs.created_at) DESC"), :test_case_id).limit(TESTS_LIMIT)
                     .pluck(:test_case_id, Arel.sql("MAX(runs.created_at)"))
        cases = @group.project.test_cases.where(id: rows.map(&:first)).index_by(&:id)
        rows.filter_map do |id, last|
          test_case = cases[id]
          test_case && { test_case_id: id, full_name: test_case.full_name, file_path: test_case.file_path,
                         last_seen_at: time(parse_time(last)) }
        end
      end
    end
  end
end
