# "Re-run failed" for one build: members and above. The answer (Builds::Rerun's message) comes
# back as the flash on the build page, or on a failed-test card when the tap came from one.
class BuildRerunsController < ApplicationController
  CARD_ANCHOR = /\A#test_result_\d+\z/

  before_action { require_role!(:member) }

  def create
    build = current_project.builds.find(params[:build_id])
    outcome = Builds::Rerun.call(build: build, user: Current.user)
    redirect_to project_build_path(current_project, build, anchor: card_anchor),
                (outcome.ok ? { notice: outcome.message } : { alert: outcome.message })
  end

  private

  def card_anchor
    value = params[:return_to].to_s
    value.delete_prefix("#") if CARD_ANCHOR.match?(value)
  end
end
