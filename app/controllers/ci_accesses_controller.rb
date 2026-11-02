# The project's GitHub token for re-running failed jobs. Admins and owners only; the
# token is write-only: it is never rendered back.
class CiAccessesController < ApplicationController
  before_action { require_role!(:admin) }
  before_action :set_ci_access

  def show; end

  def update
    attempts = 0
    begin
      @ci_access.assign_attributes(token: token_param, token_saved_at: Time.current,
                                   checked_at: nil, check_ok: nil, check_message: nil)
      if @ci_access.save
        redirect_to project_ci_access_path(current_project), notice: "Token saved."
      else
        @ci_access.restore_attributes
        @invalid = true
        render :show, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotUnique
      attempts += 1
      raise if attempts > 1
      @ci_access = CiAccess.find_by!(project: current_project)
      retry
    end
  end

  def destroy
    @ci_access.destroy if @ci_access.persisted?
    redirect_to project_ci_access_path(current_project), notice: "Token removed."
  end

  def test
    return redirect_to(project_ci_access_path(current_project), alert: "Add a GitHub token in CI access first.") unless @ci_access.persisted?

    owner, repo, = target_parts
    return redirect_to(project_ci_access_path(current_project), notice: "Saved. Test it after the first GitHub Actions build arrives.") unless owner

    response = Github::Client.new(@ci_access.token).repository(owner, repo)
    ok = response.status == 200
    message = ok ? "GitHub accepted the token and can see #{owner}/#{repo}. Re-runs also need Actions: Read and write." : failure_copy(response.status)
    @ci_access.update!(checked_at: Time.current, check_ok: ok, check_message: message)
    redirect_to project_ci_access_path(current_project), (ok ? { notice: message } : { alert: message })
  end

  private

  def set_ci_access
    @ci_access = current_project.ci_access || current_project.build_ci_access
  end

  def token_param
    params.expect(ci_access: [ :token ])[:token].to_s.strip
  end

  def target_parts
    current_project.builds.where(provider: "github_actions").where.not(ci_run_key: nil)
                   .order(id: :desc).limit(50).each do |build|
      parts = Github::Repository.from_build(build)
      return parts if parts
    end
    nil
  end

  def failure_copy(status)
    case status
    when 401 then "GitHub rejected the token. Replace it in CI access."
    when 403 then "GitHub refused: the token needs Actions: Read and write for this repository."
    when 404 then "GitHub can't find this repository, or the token can't see it."
    when 429, 500..599 then "GitHub is busy. Try again in a minute."
    when :network then "Couldn't reach GitHub."
    else "GitHub answered unexpectedly (HTTP #{status})."
    end
  end
end
