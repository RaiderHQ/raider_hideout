class Build < ApplicationRecord
  belongs_to :project
  belongs_to :baseline_build, class_name: "Build", optional: true
  has_many :runs, dependent: :destroy
  has_many :notification_deliveries, dependent: :destroy

  validates :build_key, presence: true, uniqueness: { scope: :project_id }

  after_create_commit -> { broadcast_prepend_later_to [ project, :builds ], target: "builds", partial: "builds/build", locals: { build: self } }
  after_update_commit -> { broadcast_replace_later_to [ project, :builds ], partial: "builds/build", locals: { build: self } },
                      if: :saved_changes?

  def recompute!
    totals = runs.pick(
      Arel.sql("COALESCE(SUM(total_count), 0)"), Arel.sql("COALESCE(SUM(passed_count), 0)"),
      Arel.sql("COALESCE(SUM(failed_count), 0)"), Arel.sql("COALESCE(SUM(skipped_count), 0)"),
      Arel.sql("COALESCE(SUM(pending_count), 0)"), Arel.sql("COALESCE(SUM(quarantined_count), 0)"),
      Arel.sql("MIN(started_at)"), Arel.sql("MAX(finished_at)"), Arel.sql("COUNT(*)"), Arel.sql("MAX(shard_total)")
    )
    total, passed, failed, skipped, pending, quarantined, started, finished, run_count, shard_total = totals
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
    TestCaseVerdict.for_cases(TestResult.where(run_id: runs.select(:id)).select(:test_case_id),
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
    !expected_shards || runs.size >= expected_shards
  end

  def ready_to_notify?
    return false unless complete?

    # Reuse already-loaded runs (the build page loads them) instead of another query.
    runs.loaded? ? runs.none? { |run| run.flakiness_analyzed_at.nil? } : !runs.where(flakiness_analyzed_at: nil).exists?
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

    "#{runs.size}/#{expected_shards}"
  end

  private

  def recomputed_status(failed, run_count, expected)
    if failed.positive? || runs.where(status: "failed").exists? then "failed"
    elsif expected && run_count < expected then "incomplete"
    else "passed"
    end
  end
end
