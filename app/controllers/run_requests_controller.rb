# Run tests: a member starts the project's test workflow on GitHub Actions for a branch or tag.
# The same Turbo form serves the browser and the Raider app.
class RunRequestsController < ApplicationController
  BRANCH_SUGGESTIONS = 10

  before_action { require_role!(:member) }
  before_action :require_setup

  def new
    @ref = default_ref
  end

  def create
    values = params.expect(run_request: %i[ref tags])
    outcome = Projects::RunTests.call(project: current_project, user: Current.user, ref: values[:ref], tags: values[:tags])
    if outcome.ok
      redirect_to project_builds_path(current_project), notice: outcome.message, status: :see_other
    else
      @ref = values[:ref]
      @tags = values[:tags]
      flash.now[:alert] = outcome.message
      render :new, status: :unprocessable_content
    end
  end

  private

  def require_setup
    @ci_access = current_project.ci_access
    return if @ci_access&.run_tests_ready?

    redirect_to project_builds_path(current_project), alert: Projects::RunTests.setup_copy(current_project, Current.user), status: :see_other
  end

  def default_ref
    current_project.builds.where.not(default_branch: [ nil, "" ]).order(id: :desc).pick(:default_branch) || "main"
  end

  def branch_suggestions
    current_project.builds.where.not(branch: [ nil, "" ]).order(id: :desc).limit(200).pluck(:branch).uniq.first(BRANCH_SUGGESTIONS)
  end
  helper_method :branch_suggestions
end
