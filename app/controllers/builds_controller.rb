class BuildsController < ApplicationController
  def index
    builds = current_project.builds.includes(:project, :runs).order(created_at: :desc, id: :desc)
    builds = builds.where(branch: params[:branch]) if params[:branch].present?
    @branches = current_project.builds.distinct.where.not(branch: nil).order(:branch).pluck(:branch)
    @pagy, @builds = pagy(builds, limit: 25)
  end

  def show
    @build = current_project.builds.find(params[:id])
    @runs = Run.in_shard_order(@build.runs.to_a)
    results = TestResult.where(run_id: @build.runs.select(:id))
                        .includes(:test_case, { run: :project }, attachments_attachments: :blob)
    @groups = TestResult.grouped_for_display(results)
    @verdicts = TestCaseVerdict.for_cases(TestResult.where(run_id: @build.runs.select(:id)).select(:test_case_id),
                                          branch: @build.branch, default_branch: @build.comparison_branch)
    load_error_groups
    @comparison = Builds::Comparison.new(@build) if @build.ready_to_notify? && @build.baseline_assigned_at && !@build.results_expired?
    @gate_report = @build.gate_report
    @gate_rule_enabled = current_project.gate_enabled?
  end

  private

  # Failed or quarantined, grouped results of this build keyed by error group (from the loaded
  # results: no extra query), and one project-scoped ErrorGroup load, skipped when
  # no failed result is grouped.
  def load_error_groups
    failed = @groups.flat_map(&:last).select { |r| TestResult::FAILING_STATUSES.include?(r.status) && r.error_group_id }.group_by(&:error_group_id)
    @error_groups = failed.empty? ? {} : current_project.error_groups.where(id: failed.keys).index_by(&:id)
    @failed_by_group = failed.slice(*@error_groups.keys)
    @group_counts = @failed_by_group.transform_values(&:size)
  end
end
