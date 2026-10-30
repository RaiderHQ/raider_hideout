module Api
  module V1
    # §5.3 build list shape and §5.4 build detail.
    class BuildPresenter < BasePresenter
      include BuildsHelper

      FAILURES_LIMIT = 200
      FAILURE_MESSAGE_LIMIT = 1_000
      COMPARISON_IDS_LIMIT = 100
      UNAVAILABLE_COMPARISON = { available: false, baseline_build_id: nil, branch: nil, counts: nil,
                                 new_failure_test_ids: nil, still_failing_test_ids: nil }.freeze

      # Builds and runs carry the same count columns.
      def self.counts(record)
        { total: record.total_count, passed: record.passed_count, failed: record.failed_count, skipped: record.skipped_count,
          pending: record.pending_count, flaky: record.flaky_count, quarantined: record.quarantined_count }
      end

      def initialize(build, url_options:)
        super(url_options: url_options)
        @build = build
      end

      def to_h
        {
          id: @build.id, build_key: @build.build_key, branch: @build.branch, commit_sha: @build.commit_sha,
          commit_message: @build.commit_message, status: @build.status, counts: self.class.counts(@build),
          pass_rate: @build.pass_rate, gate_status: @build.gate_report.state, duration_ms: @build.duration_ms,
          pr: @build.pr_number && { number: @build.pr_number, url: pull_request_url(@build) },
          ci_url: @build.ci_url, url: url(:project_build_url, @build.project, @build), created_at: time(@build.created_at)
        }
      end

      def detail
        to_h.merge(gate: gate, comparison: comparison, failures: failures, shards: shards, results_purged: @build.results_expired?)
      end

      private

      def gate
        report = @build.gate_report
        { state: report.state, rules: report.rules.map { |rule| { rule: rule.rule, outcome: rule.outcome, detail: rule.detail } } }
      end

      def comparison
        comparison = usable_comparison
        return UNAVAILABLE_COMPARISON unless comparison

        { available: true, baseline_build_id: comparison.baseline.id, branch: comparison.branch, counts: comparison.counts,
          new_failure_test_ids: comparison.new_failures.first(COMPARISON_IDS_LIMIT).map(&:id),
          still_failing_test_ids: comparison.still_failing.first(COMPARISON_IDS_LIMIT).map(&:id) }
      end

      # The build page's rule: a ready build with a frozen baseline, and neither side's results purged.
      def usable_comparison
        return unless @build.ready_to_notify? && @build.baseline_assigned_at && !@build.results_expired?

        comparison = Builds::Comparison.new(@build)
        comparison if comparison.available? && !comparison.expired?
      end

      # Failed first, then quarantined; by file, then name.
      def failures
        TestResult.where(run_id: @build.runs.select(:id), status: TestResult::FAILING_STATUSES)
                  .joins(:test_case).preload(:test_case)
                  .order(Arel.sql("CASE test_results.status WHEN 'failed' THEN 0 ELSE 1 END"),
                         "test_cases.file_path", "test_cases.full_name", "test_results.id")
                  .limit(FAILURES_LIMIT).map { |result| failure(result) }
      end

      def failure(result)
        test_case = result.test_case
        {
          test_case_id: result.test_case_id, full_name: test_case.full_name, file_path: test_case.file_path,
          line_number: test_case.line_number, status: result.status, exception_class: result.exception_class,
          message: clip(result.failure_message, FAILURE_MESSAGE_LIMIT), error_group_id: result.error_group_id,
          attempts: result.attempts, app_frame: result.app_frame.presence || Failures::Signature.fallback_frame(result.backtrace)
        }
      end

      def shards
        Run.in_shard_order(@build.runs.to_a).map do |run|
          { index: run.shard_index, total: run.shard_total, label: run.shard_label, status: run.status,
            counts: self.class.counts(run) }
        end
      end
    end
  end
end
