module Builds
  # Asks GitHub to re-run the failed jobs of a build's workflow run and records the answer.
  #
  # The guard check and the row insert share one transaction under `build.lock!`, and the
  # GitHub call happens inside it: a second tap on a database that really locks (PostgreSQL)
  # waits for the first, then sees its `accepted` row and answers with the guard copy instead
  # of calling GitHub again. The call holds a row lock for at most the 10 s timeouts.
  class Rerun
    Outcome = Data.define(:ok, :message, :rerun)

    NO_TOKEN = "Add a GitHub token in CI access first.".freeze
    NOT_RERUNNABLE = "This build can't be re-run from Hideout.".freeze
    COPY = {
      401 => "GitHub rejected the token. Replace it in CI access.",
      403 => "GitHub refused: the token needs Actions: Read and write for this repository.",
      404 => "GitHub can't find this run, or the token can't see the repository.",
      409 => "GitHub can't re-run this run now (it may still be running or be too old).",
      422 => "GitHub can't re-run this run now (it may still be running or be too old)."
    }.freeze
    BUSY = "GitHub is busy. Try again in a minute.".freeze
    NETWORK = "Couldn't reach GitHub.".freeze

    def self.call(build:, user:) = new(build, user).call

    def initialize(build, user)
      @build = build
      @user = user
    end

    def call
      @build.transaction do
        @build.lock!
        check = precheck
        next check if check

        request_rerun
      end
    end

    private

    def precheck
      return refuse(NO_TOKEN) unless @build.project.ci_access
      return refuse(NOT_RERUNNABLE) unless @build.rerunnable?

      pending = @build.pending_rerun
      refuse("A re-run was already requested at #{pending.created_at.strftime('%H:%M')}.") if pending
    end

    def request_rerun
      access = @build.project.ci_access
      owner, repo, run_id = Github::Repository.from_build(@build)
      attempt_before = @build.latest_attempt
      response = Github::Client.new(access.token).rerun_failed_jobs(owner, repo, run_id)
      status = status_for(response.status)
      message = response.message && access.redact(response.message)[0, BuildRerun::MAX_MESSAGE]
      http = response.status.is_a?(Integer) ? response.status : nil
      rerun = @build.reruns.create!(user: @user, attempt_before: attempt_before, status: status,
                                    http_status: http, message: message)
      Outcome.new(ok: status == "accepted", message: copy_for(response.status, attempt_before), rerun: rerun)
    rescue Github::Client::Error
      refuse(NOT_RERUNNABLE)
    end

    def status_for(code)
      return "failed" unless code.is_a?(Integer)

      if code.between?(200, 299) then "accepted"
      elsif code == 429 || code >= 500 then "failed"
      elsif code.between?(400, 499) then "rejected"
      else "failed"
      end
    end

    def copy_for(code, attempt_before)
      return NETWORK if code == :network
      return "Re-run requested. The result arrives as attempt #{attempt_before + 1}." if code.between?(200, 299)

      COPY.fetch(code, BUSY)
    end

    def refuse(message) = Outcome.new(ok: false, message: message, rerun: nil)
  end
end
