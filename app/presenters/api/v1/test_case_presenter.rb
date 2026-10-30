module Api
  module V1
    # §5.5 test row and §5.6 test detail.
    class TestCasePresenter < BasePresenter
      RESULTS_LIMIT = 20
      EVENTS_LIMIT = 20
      MESSAGE_LIMIT = 300

      def initialize(test_case, url_options:)
        super(url_options: url_options)
        @test_case = test_case
      end

      # row: this test's Search::TestsQuery::Row.
      def row(row, quarantined:)
        identity.merge(last_status: row.latest_status, pass_rate: row.pass_rate, failures: row.failures,
                       avg_duration_ms: row.avg_duration_ms, last_run_at: time(row.last_run_at), flaky: row.flaky,
                       quarantined: quarantined)
      end

      # row is nil when the test did not run on the default branch in Explore's default range.
      def detail(row, quarantine:)
        base = row ? row(row, quarantined: quarantine.present?) : not_run(quarantined: quarantine.present?)
        base.merge(results: results, verdicts: verdicts, quarantine: quarantine && quarantine_fields(quarantine),
                   quarantine_events: events)
      end

      # §5.9: one entry of the flaky list.
      def flaky(verdict)
        { test_case_id: @test_case.id, full_name: @test_case.full_name, file_path: @test_case.file_path,
          flip_rate: verdict.flip_rate, flaky_reason: verdict.flaky_reason, sample_count: verdict.sample_count,
          flaky_since_build_id: verdict.flaky_since_build_id }
      end

      private

      def identity
        { id: @test_case.id, full_name: @test_case.full_name, file_path: @test_case.file_path, line_number: @test_case.line_number }
      end

      def not_run(quarantined:)
        flaky = TestCaseVerdict.exists?(test_case_id: @test_case.id, branch: @test_case.project.default_branch, flaky: true)
        identity.merge(last_status: @test_case.last_status, pass_rate: nil, failures: 0, avg_duration_ms: nil,
                       last_run_at: nil, flaky: flaky, quarantined: quarantined)
      end

      def results
        @test_case.test_results.joins(:run).preload(:run).order("runs.created_at DESC, test_results.id DESC")
                  .limit(RESULTS_LIMIT).map do |result|
          { build_id: result.run.build_id, run_id: result.run_id, branch: result.run.branch, status: result.status,
            duration_ms: result.duration_ms, message: clip(result.failure_message, MESSAGE_LIMIT),
            created_at: time(result.run.created_at) }
        end
      end

      def verdicts
        @test_case.verdicts.order(:branch).map do |verdict|
          { branch: verdict.branch, flaky: verdict.flaky, flaky_reason: verdict.flaky_reason, flip_rate: verdict.flip_rate,
            sample_count: verdict.sample_count }
        end
      end

      def quarantine_fields(quarantine)
        { reason: quarantine.reason, expires_at: time(quarantine.expires_at), quarantined_by: quarantine.created_by&.email_address }
      end

      def events
        QuarantineEvent.where(quarantine_id: @test_case.quarantines.select(:id)).includes(:actor).newest_first
                       .limit(EVENTS_LIMIT).map do |event|
          { action: event.action, note: event.note, actor: event.actor&.email_address, created_at: time(event.created_at) }
        end
      end
    end
  end
end
