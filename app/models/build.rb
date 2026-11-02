class Build < ApplicationRecord
  belongs_to :project
  belongs_to :baseline_build, class_name: "Build", optional: true
  has_many :runs, dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy
  has_many :reruns, class_name: "BuildRerun", dependent: :delete_all

  # Time attempt-N runs must stay quiet before their notification, so a re-run's late shards land first.
  ATTEMPT_QUIET_PERIOD = 2.minutes
  # A re-run attempt below its failed-run floor (single "Re-run job") is ready after this much quiet.
  # Stays well under the reporter gate's 600 s default timeout.
  ATTEMPT_FLOOR_FALLBACK = 5.minutes

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
    if runs.distinct.count(:attempt) > 1
      scope.update_all("superseded = #{SUPERSEDED_SQL}")
    else
      scope.where(superseded: true).update_all(superseded: false)
    end
  end

  # Effective passed results whose test failed in an earlier attempt: [[result, attempt that fixed it]].
  # A fixed slot is the same test in the same shard_label; four queries however many tests were fixed.
  def fixed_by_rerun
    failed_slots = TestResult.where(run_id: runs.select(:id), superseded: true, status: "failed").joins(:run)
                             .pluck(:test_case_id, Arel.sql("COALESCE(runs.shard_label, '')")).to_set
    return [] if failed_slots.empty?

    TestResult.where(run_id: runs.select(:id), superseded: false, status: "passed")
              .where(test_case_id: failed_slots.map(&:first).uniq)
              .joins(:test_case).includes(:test_case, :run)
              .order("test_cases.full_name", "test_results.id")
              .select { |result| failed_slots.include?([ result.test_case_id, result.run.shard_label.to_s ]) }
              .map { |result| [ result, result.run.attempt ] }
  end

  AttemptSummary = Data.define(:attempt, :status, :ready, :run_count, :counts, :created_at, :ci_url)

  # One summary per attempt, oldest first, built from the runs (no per-attempt queries when loaded).
  def attempt_summaries
    all_runs = runs.to_a
    all_runs.group_by(&:attempt).sort.map do |attempt, group|
      counts = group.map { |run| Api::V1::BuildPresenter.counts(run) }.reduce { |sum, one| sum.merge(one) { |_k, a, b| a + b } }
      AttemptSummary.new(
        attempt: attempt, status: group.any? { |run| run.status == "failed" } ? "failed" : "passed",
        ready: attempt_ready?(attempt), run_count: group.size, counts: counts,
        created_at: group.map(&:created_at).min, ci_url: ci_run_key.present? && ci_url.present? ? "#{ci_url}/attempts/#{attempt}" : ci_url
      )
    end
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
    shard_total = first_runs.maximum(:shard_total)
    run_count = received_shard_count
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

  # Shards received: first-attempt runs, plus later-attempt runs whose non-nil shard_label
  # never appeared in the first attempt (a re-run filling a shard that crashed before uploading).
  # Unlabeled later runs cannot be matched to a missing shard, so they do not count.
  def received_shard_count
    rows = runs.loaded? ? runs.map { |run| [ run.attempt, run.shard_label ] } : runs.pluck(:attempt, :shard_label)
    first = rows.map(&:first).min || 1
    first_rows, later_rows = rows.partition { |attempt, _| attempt == first }
    seen = first_rows.filter_map(&:last).to_set
    first_rows.size + (later_rows.filter_map(&:last).uniq.reject { |label| seen.include?(label) }).size
  end

  def complete?
    !expected_shards || received_shard_count >= expected_shards
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
  # The one guard for "is this attempt a re-run": readiness, the page and the message all use it.
  def rerun_attempt?(attempt)
    ci_run_key.present? && attempt > first_attempt
  end

  # The first attempt follows ready_to_notify?. A later attempt is ready once its runs cover the
  # previous attempt's failed runs, are all analysed, and have been quiet for ATTEMPT_QUIET_PERIOD;
  # below that floor it is ready once all are analysed and quiet for ATTEMPT_FLOOR_FALLBACK.
  def attempt_ready?(attempt)
    return ready_to_notify? unless rerun_attempt?(attempt)

    pair = runs.loaded? ? runs.to_a : runs.where(attempt: [ attempt - 1, attempt ]).to_a
    mine = pair.select { |run| run.attempt == attempt }
    floor = [ 1, pair.count { |run| run.attempt == attempt - 1 && run.status == "failed" } ].max
    return false if mine.empty? || mine.any? { |run| run.flakiness_analyzed_at.nil? }

    newest = mine.map(&:flakiness_analyzed_at).max
    (mine.size >= floor && newest <= ATTEMPT_QUIET_PERIOD.ago) || newest <= ATTEMPT_FLOOR_FALLBACK.ago
  end

  RERUN_GUARD = 10.minutes

  # Offered only for a GitHub Actions build that failed, whose run key parses to safe parts and
  # whose project has a token. The viewer's role is checked by the caller.
  def rerunnable?
    provider == "github_actions" && status == "failed" && !Github::Repository.from_build(self).nil? &&
      project.ci_access.present?
  end

  # The accepted re-run still in flight: no newer attempt has arrived and it is under 10 minutes old.
  def pending_rerun
    reruns.where(status: "accepted", attempt_before: latest_attempt)
          .where("created_at > ?", RERUN_GUARD.ago).order(:created_at).last
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

    "#{received_shard_count}/#{expected_shards}"
  end

  private

  def recomputed_status(failed, run_count, expected)
    if failed.positive? then "failed"
    elsif expected && run_count < expected then "incomplete"
    else "passed"
    end
  end
end
