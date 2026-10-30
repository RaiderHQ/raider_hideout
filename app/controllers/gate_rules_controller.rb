# The project's quality gate settings (spec §4.5): every member role can view, only
# admins and owners can change them.
class GateRulesController < ApplicationController
  before_action(only: :update) { require_role!(:admin) }
  before_action :set_gate_rule

  def show; end

  def update
    if save_gate_rule
      redirect_to project_gate_path(current_project), notice: "Gate rules saved. They apply to builds evaluated from now on."
    else
      render :show, status: :unprocessable_content
    end
  end

  private

  # Two admins saving for the first time can race on the unique index; the loser retries
  # once against the row the winner created. updated_by changes only with a successful
  # save, so a 422 re-render still names whoever last changed the rules.
  def save_gate_rule
    attempts = 0
    begin
      @gate_rule.assign_attributes(gate_rule_params)
      @gate_rule.updated_by = Current.user
      @gate_rule.save.tap { |saved| @gate_rule.restore_attributes(%i[updated_by_id]) unless saved }
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      raise if attempts > 1
      @gate_rule = GateRule.find_by!(project: current_project)
      retry
    end
  end

  def set_gate_rule
    @gate_rule = current_project.gate_rule || current_project.build_gate_rule
  end

  def gate_rule_params
    params.expect(gate_rule: %i[min_pass_rate no_new_failures no_new_flaky])
  end
end
