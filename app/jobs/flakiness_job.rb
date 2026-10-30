class FlakinessJob < ApplicationJob
  queue_as :default

  retry_on ActiveRecord::StatementInvalid, wait: :polynomially_longer, attempts: 5

  def perform(run_id)
    run = Run.find_by(id: run_id)
    return unless run

    run.test_cases.each { |test_case| update(test_case, run) } if run.branch.present?
    run.update!(flaky_count: flaky_count(run))
    run.build.recompute!
    run.update_column(:flakiness_analyzed_at, Time.current)
    build = run.build.reload
    return unless build.ready_to_notify?

    Builds::Baseline.assign!(build)
    Builds::Gate.evaluate!(build)
    NotifyBuildJob.perform_later(build.id)
  end

  private

  # Writes the verdict for the run's branch only; a run without a branch writes none.
  def update(test_case, run)
    rows = test_case.test_results.joins(:run).where(runs: { branch: run.branch })
                    .where(status: Flakiness::Analyzer::EXECUTED)
                    .order("runs.created_at DESC, test_results.id DESC")
                    .limit(Flakiness::Analyzer::WINDOW)
                    .pluck(:status, "runs.commit_sha", :retried_flaky)
    samples = rows.reverse.map { |status, sha, retried| Flakiness::Sample.new(status: status, commit_sha: sha, retried_flaky: retried) }
    verdict = Flakiness::Analyzer.call(samples)
    TestCaseVerdict.upsert(
      { test_case_id: test_case.id, branch: run.branch, flaky: verdict.flaky, flaky_reason: verdict.reason,
        flip_rate: verdict.flip_rate, sample_count: samples.size },
      unique_by: %i[test_case_id branch]
    )
    track_flaky_since(TestCaseVerdict.where(test_case_id: test_case.id, branch: run.branch), run, verdict, samples.size)
  end

  # flaky_since_build_id is set once and only cleared on a well-sampled verdict, so a
  # sparsely-sampled run cannot flap the branch's row and re-announce a known flaky test.
  def track_flaky_since(row, run, verdict, sample_count)
    if verdict.flaky
      # Also require flaky: a concurrent not-flaky upsert must not leave a since on a clear row.
      row.where(flaky_since_build_id: nil, flaky: true).update_all(flaky_since_build_id: run.build_id)
    elsif sample_count >= Flakiness::Analyzer::MIN_SAMPLES
      row.update_all(flaky_since_build_id: nil)
    end
  end

  def flaky_count(run)
    TestCaseVerdict.for_cases(run.test_results.select(:test_case_id), branch: run.branch,
                              default_branch: run.build.comparison_branch).count { |_id, verdict| verdict.flaky }
  end
end
