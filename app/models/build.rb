class Build < ApplicationRecord
  belongs_to :project
  belongs_to :baseline_build, class_name: "Build", optional: true
  has_many :runs, dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy

  # Time attempt-N runs must stay quiet before their notification, so a re-run's late shards land first.
  ATTEMPT_QUIET_PERIOD = 2.minutes

  validates :build_key, presence: true, uniqueness: { scope: :project_id }

  after_create_commit -> { broadcast_prepend_later_to [ project, :builds ], target: "builds", partial: "builds/build", locals: { build: self } }
  after_update_commit -> { broadcast_replace_later_to [ project, :builds ], partial: "builds/build", locals: { build: self } },
                      if: :saved_changes?

  SUPERSEDED_SQL = <<~SQL.squish.freeze
    EXISTS (
      SELECT 1 FROM test_results newer
      JOIN runs newer_run ON newer_run.id = newer.run_id
      JOIN runs own_run ON own_run.id = test_results.run_id
      WHERE newer_run.build_id = own_run.build_id
        AND newer.test_case_id = test_results.test_case_id
        AND COALESCE(newer_run.shard_label, '') = COALESCE(own_run.shard_label, '')
        AND newer_run.attempt > own_run.attempt
    )
  SQL

  # Results not replaced by a later attempt of the same test in the same slot (shard_label).
  def effective_results
    TestResult.where(run_id: runs.select(:id), superseded: false)
  end

  # Attempt 1 defines the build's shard expectations. When attempt 1 never uploaded,
  # the lowest attempt present stands in so the build can still complete.
  def first_attempt_runs
    first = runs.minimum(:attempt)
    runs.where(attempt: first || 1)
  end

  # The lowest attempt present; 1 when the build has no runs.
  def first_attempt
    runs.loaded? ? (runs.map(&:attempt).min || 1) : (runs.minimum(:attempt) || 1)
  end

  def mark_superseded!
    scope = TestResult.where(run_id: runs.select(:id))
    if runs.where("attempt > 1").exists?
      scope.update_all("superseded = #{SUPERSEDED_SQL}")
    else
      scope.where(superseded: true).update_all(superseded: false)
    end
  end

  # Effective passed results whose test failed in an earlier attempt: [[result, attempt that fixed it]].
  def fixed_by_rerun
    superseded_failed = TestResult.where(run_id: runs.select(:id), superseded: true, status: "failed")
    TestResult.where(run_id: runs.select(:id), superseded: false, status: "passed")
              .where(test_case_id: superseded_failed.select(:test_case_id))
              .joins(:test_case, :run).includes(:test_case, :run)
              .order("test_cases.full_name", "test_results.id")
              .select { |result| fixed_slot?(result, superseded_failed) }
              .map { |result| [ result, result.run.attempt ] }
  end

  def recompute!
    mark_superseded!
    totals = runs.pick(
      Arel.sql("COALESCE(SUM(total_count), 0)"), Arel.sql("COALESCE(SUM(passed_count), 0)"),
      Arel.sql("COALESCE(SUM(failed_count), 0)"), Arel.sql("COALESCE(SUM(skipped_count), 0)"),
      Arel.sql("COALESCE(SUM(pending_count), 0)"), Arel.sql("COALESCE(SUM(quarantined_count), 0)"),
      Arel.sql("MIN(started_at)"), Arel.sql("MAX(finished_at)")
    )
    total, passed, failed, skipped, pending, quarantined, started, finished = totals
    first_runs = first_attempt_runs
    run_count, shard_total = first_runs.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(shard_total)"))
    dropped = TestResult.where(run_id: runs.select(:id), superseded: true).group(:status).count
    total -= dropped.values.sum
    passed -= dropped.fetch("passed", 0)
    failed -= dropped.fetch("failed", 0)
    skipped -= dropped.fetch("skipped", 0)
    pending -= dropped.fetch("pending", 0)
    quarantined -= dropped.fetch("quarantined", 0)
    started, finished = [ started, finished ].map { |t| t.is_a?(String) ? Time.zone.parse("#{t} UTC") : t }
    flaky = flaky_test_case_ids.size
    expected = synthetic? ? nil : [ expected_shards, shard_total ].compact.max

    update!(
      total_count: total, passed_count: passed, failed_count: failed, skipped_count: skipped, pending_count: pending,
      quarantined_count: quarantined,
      flaky_count: flaky, started_at: started, finished_at: finished,
      duration_ms: (started && finished ? ((finished - started) * 1000).round : nil),
      expected_shards: expected,
      status: recomputed_status(failed, run_count, expected)
    )
  end

  # The branch this build is compared with: the CI-reported default branch, the PR
  # base, else main/master when the project has builds there.
  def comparison_branch
    return @comparison_branch if defined?(@comparison_branch)

    @comparison_branch = default_branch.presence || pr_base_branch.presence || project.conventional_branch
  end

  def reload(*)
    remove_instance_variable(:@comparison_branch) if defined?(@comparison_branch)
    super
  end

  # Test cases of this build whose verdict on its branch (or the fallback) is flaky.
  def flaky_test_case_ids
    TestCaseVerdict.for_cases(effective_results.select(:test_case_id),
                              branch: branch, default_branch: comparison_branch)
                   .select { |_id, verdict| verdict.flaky }.keys
  end

  # A build without a CI build_key ("run:<client_run_id>") holds exactly one run,
  # so a local shard total must not make it wait for siblings that never come.
  def synthetic?
    build_key.to_s.start_with?("run:")
  end

  # True once every run's test results were purged by retention; counts remain.
  def results_expired?
    runs.exists? && !runs.where(results_purged_at: nil).exists?
  end

  def complete?
    !expected_shards || first_attempt_run_count >= expected_shards
  end

  # Every first-attempt run analysed; later attempts notify on their own (attempt_ready?).
  def ready_to_notify?
    return false unless complete?

    # Reuse already-loaded runs (the build page loads them) instead of another query.
    if runs.loaded?
      first = first_attempt
      runs.none? { |run| run.attempt == first && run.flakiness_analyzed_at.nil? }
    else
      !first_attempt_runs.where(flakiness_analyzed_at: nil).exists?
    end
  end

  # A GitHub re-run of a build whose earlier attempt is present: notified separately, after a quiet period.
  def rerun_attempt?(attempt)
    ci_run_key.present? && attempt > first_attempt
  end

  # The first attempt follows ready_to_notify?. A later attempt is ready once its runs cover the
  # previous attempt's failed runs, are all analysed, and have been quiet for ATTEMPT_QUIET_PERIOD.
  def attempt_ready?(attempt)
    return ready_to_notify? if attempt <= first_attempt

    mine = runs.where(attempt: attempt)
    floor = [ 1, runs.where(attempt: attempt - 1, status: "failed").count ].max
    return false if mine.count < floor || mine.where(flakiness_analyzed_at: nil).exists?

    mine.maximum(:flakiness_analyzed_at) <= ATTEMPT_QUIET_PERIOD.ago
  end

  def gate_report
    Builds::GateReport.new(self)
  end

  # Quarantined results do not fail the build but do count as not passing.
  def self.pass_rate_for(passed:, failed:, quarantined:)
    executed = passed + failed + quarantined
    return nil if executed.zero?

    (passed * 100.0 / executed).round
  end

  def pass_rate = self.class.pass_rate_for(passed: passed_count, failed: failed_count, quarantined: quarantined_count)

  def duration_label
    return "–" if duration_ms.nil?
    return "<1s" if duration_ms < 1000
    return "#{(duration_ms / 100) / 10.0}s" if duration_ms < 60_000

    seconds = duration_ms / 1000
    "#{seconds / 60}m #{seconds % 60}s"
  end

  def shard_progress
    return nil unless expected_shards

    "#{first_attempt_run_count}/#{expected_shards}"
  end

  private

  # Counts without a query when the runs are already loaded (build lists, build page).
  def first_attempt_run_count
    return first_attempt_runs.count unless runs.loaded?

    first = runs.map(&:attempt).min || 1
    runs.count { |run| run.attempt == first }
  end

  def fixed_slot?(result, superseded_failed)
    superseded_failed.joins(:run).where(test_case_id: result.test_case_id)
                     .where("COALESCE(runs.shard_label, '') = ?", result.run.shard_label.to_s).exists?
  end

  def recomputed_status(failed, run_count, expected)
    if failed.positive? then "failed"
    elsif expected && run_count < expected then "incomplete"
    else "passed"
    end
  end
end
