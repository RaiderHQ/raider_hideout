# The project's GitHub token for re-running failed jobs and starting the test workflow, and
# the Run tests settings. Admins and owners only; the token is write-only: it is never
# rendered back. The settings have their own form, so saving them never needs the token.
class CiAccessesController < ApplicationController
  NO_TOKEN = "Add a GitHub token in CI access first.".freeze

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

  def settings
    return redirect_to(project_ci_access_path(current_project), alert: NO_TOKEN) unless @ci_access.persisted?

    @ci_access.assign_attributes(settings_params)
    if @ci_access.save
      redirect_to project_ci_access_path(current_project), notice: "Settings saved."
    else
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @ci_access.destroy if @ci_access.persisted?
    redirect_to project_ci_access_path(current_project), notice: "Token removed."
  end

  def test
    return redirect_to(project_ci_access_path(current_project), alert: NO_TOKEN) unless @ci_access.persisted?

    owner, repo = target_parts
    return redirect_to(project_ci_access_path(current_project), notice: "Saved. Test it after the first GitHub Actions build arrives.") unless owner

    client = Github::Client.new(@ci_access.token)
    response = client.repository(owner, repo)
    ok = response.status == 200
    message = ok ? "GitHub accepted the token and can see #{owner}/#{repo}. Re-runs and Run tests also need Actions: Read and write." : failure_copy(response.status)
    message += workflow_copy(client, owner, repo) if ok && @ci_access.workflow
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

  def settings_params
    params.expect(ci_access: %i[repository workflow tag_input])
  end

  # The saved repository first, else the one the latest GitHub Actions build reported.
  def target_parts
    @ci_access.repository_parts || CiAccess.split_repository(@ci_access.detected_repository)
  end

  def workflow_copy(client, owner, repo)
    case client.workflow(owner, repo, @ci_access.workflow).status
    when 200 then " Found #{@ci_access.workflow}."
    when 404 then " GitHub can't find #{@ci_access.workflow} in #{owner}/#{repo}."
    else ""
    end
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
