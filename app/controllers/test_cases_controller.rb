class TestCasesController < ApplicationController
  def show
    @test_case = current_project.test_cases.find(params[:id])
    @branches = @test_case.test_results.joins(:run).distinct.pluck("runs.branch").compact.sort
    @branch = params[:branch].presence || @test_case.test_results.joins(:run).order("runs.created_at DESC").pick("runs.branch")
    @results = @test_case.test_results.joins(:run).includes(:run).where(runs: { branch: @branch })
                         .order("runs.created_at DESC, test_results.id DESC")
                         .limit(Flakiness::Analyzer::WINDOW).to_a.reverse
    @verdicts = @test_case.verdicts.order(:branch).to_a
    @verdict = @test_case.verdict_for(@branch, default_branch: current_project.default_branch)
    @quarantine = @test_case.quarantines.active.includes(:created_by).first
    @quarantine_events = QuarantineEvent.where(quarantine_id: @test_case.quarantines.select(:id)).includes(:actor)
                                       .newest_first.limit(QuarantinesController::EVENTS_LIMIT)
  end
end
