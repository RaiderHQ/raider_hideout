class FlakyTestsController < ApplicationController
  def index
    verdicts = TestCaseVerdict.joins(:test_case).where(test_cases: { project_id: current_project.id })
    @branch = params[:branch].presence || current_project.default_branch
    @branches = (verdicts.distinct.pluck(:branch) | [ @branch ]).sort
    @verdicts = TestCaseVerdict.flaky_on(current_project, @branch).includes(:test_case)
    @quarantined_ids = current_project.quarantines.active.where(test_case_id: @verdicts.map(&:test_case_id))
                                      .pluck(:test_case_id).to_set
  end
end
