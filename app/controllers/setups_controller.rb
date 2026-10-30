# First-run setup (spec 2026-10-29 §5.3): only while there are no users,
# and only with the setup code from the boot log.
class SetupsController < ApplicationController
  allow_unauthenticated_access
  allow_unverified_access
  skip_before_action :redirect_to_setup
  # Both limits are declared before require_setup_code: callbacks run in declaration
  # order, and wrong-code visits must count against the limit before the locked page renders.
  rate_limit to: 10, within: 3.minutes, only: :create, name: "setup-create", with: -> { head :too_many_requests }
  # Code guesses: visits without a code (the first-run redirect) do not count.
  rate_limit to: 20, within: 3.minutes, only: :show, name: "setup-show", if: -> { params[:code].present? },
             with: -> { head :too_many_requests }
  before_action :require_setup_code

  def show
    @setup = InstanceSetup.new
  end

  def create
    @setup = InstanceSetup.new(params.expect(instance_setup: %i[email_address password password_confirmation
                                                                organization_name project_name]))
    @result = @setup.save
    return render(:show, status: :unprocessable_content) unless @result

    start_new_session_for @result.user
    response.headers["Cache-Control"] = "no-store"
    render :done
  rescue InstanceSetup::AlreadyDone
    raise ActiveRecord::RecordNotFound
  end

  private

  # Once any user exists the page is gone for good; before that, a missing or
  # wrong code gets a 404 that says where the link is (ruling R3).
  def require_setup_code
    raise ActiveRecord::RecordNotFound unless InstanceSetup.pending?

    render :locked, status: :not_found unless Hideout::SetupCode.valid?(params[:code])
  end
end
