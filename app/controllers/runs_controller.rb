class RunsController < ApplicationController
  def index
    runs = current_project.runs.newest_first
    runs = runs.where(branch: params[:branch]) if params[:branch].present?
    @branches = current_project.runs.distinct.where.not(branch: nil).order(:branch).pluck(:branch)
    @pagy, @runs = pagy(runs, limit: 25)
  end

  def show
    @run = current_project.runs.includes(:build).find(params[:id])
    @groups = TestResult.grouped_for_display(@run.test_results.includes(:test_case, :run, attachments_attachments: :blob))
    @verdicts = TestCaseVerdict.for_cases(@run.test_results.select(:test_case_id),
                                          branch: @run.branch, default_branch: @run.build.comparison_branch)
  end
end
