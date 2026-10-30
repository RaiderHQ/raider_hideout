class ApiTokensController < ApplicationController
  before_action(only: %i[create destroy]) { require_role!(:member) }

  def index
    @tokens = current_project.api_tokens.order(created_at: :desc)
  end

  def create
    name = params.expect(api_token: [ :name ])[:name].presence || "CI"
    @token, @plaintext = ApiToken.issue!(project: current_project, name: name)
    response.headers["Cache-Control"] = "no-store"
    render :create
  end

  def destroy
    current_project.api_tokens.find(params[:id]).destroy!
    redirect_to project_api_tokens_path(current_project), notice: "Token revoked."
  end
end
