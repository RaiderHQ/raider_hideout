module Projects
  # Starts the project's test workflow on GitHub Actions (workflow_dispatch) and records the
  # request, following Builds::Rerun's two steps so no database lock is held across the network:
  #
  # 1. a short transaction under `ci_access.lock!`: the double-tap guard, the hourly cap, and a
  #    `pending` row (which both guards count, so a second tap sees it);
  # 2. the GitHub call outside any transaction (SQLite's write lock is database-wide and the
  #    call can take 10 s+), then `update_columns` to settle the row.
  class RunTests
    Outcome = Data.define(:ok, :message, :request)

    DOUBLE_TAP = 60.seconds
    HOURLY_CAP = 10
    SET_UP = "Set up Run tests in CI access.".freeze
    ASK_ADMIN = "Ask an admin to set up Run tests in CI access.".freeze
    BAD_REF = "Enter a branch or tag name.".freeze
    BAD_TAGS = "Use letters, numbers, @, :, commas and spaces.".freeze
    CAPPED = "This project already started #{HOURLY_CAP} runs in the last hour. Try again later.".freeze
    COPY = {
      401 => "GitHub rejected the token. Replace it in CI access.",
      403 => "GitHub refused: the token needs Actions: Read and write for this repository.",
      404 => "GitHub can't find this workflow, or the token can't see the repository. Check CI access."
    }.freeze
    REFUSED = "GitHub refused the run. Check the branch or tag and the workflow's inputs.".freeze
    BUSY = "GitHub is busy. Try again in a minute.".freeze
    NETWORK = "Couldn't reach GitHub.".freeze

    def self.call(project:, user:, ref:, tags:) = new(project, user, ref, tags).call

    # The copy for a GitHub answer that wasn't accepted: an HTTP code (nil when there was no
    # answer) and GitHub's redacted message.
    def self.error_copy(code, message = nil)
      return NETWORK unless code.is_a?(Integer)
      return COPY.fetch(code) if COPY.key?(code)
      return BUSY if code == 429 || code >= 500 || code < 400

      message.present? ? "GitHub refused the run: #{message}" : REFUSED
    end

    # Admins can fix the setup themselves; members are told to ask.
    def self.setup_copy(project, user)
      role = user&.role_in(project.organization)
      role && Membership::RANK.fetch(role) >= Membership::RANK.fetch("admin") ? SET_UP : ASK_ADMIN
    end

    def initialize(project, user, ref, tags)
      @project = project
      @user = user
      @ref = ref.to_s.strip
      @tags = tags.to_s.strip.presence
    end

    def call
      access = @project.ci_access
      return refuse(self.class.setup_copy(@project, @user)) unless access&.run_tests_ready?

      @tags = nil unless access.tag_input
      return refuse(BAD_REF) unless RunRequest::REF_FORMAT.match?(@ref)
      return refuse(BAD_TAGS) if @tags && !RunRequest::TAGS_FORMAT.match?(@tags)

      request = nil
      refusal = access.transaction do
        access.lock!
        check = guard
        next check if check

        request = @project.run_requests.create!(user: @user, ref: @ref, tags: @tags, repository: access.repository,
                                                workflow: access.workflow, status: "pending")
        nil
      end
      refusal || dispatch(access, request)
    end

    private

    def guard
      live = @project.run_requests.live
      recent = live.where(ref: @ref, tags: @tags).where("created_at > ?", DOUBLE_TAP.ago).order(:created_at).last
      return refuse("Tests on #{@ref} were already requested at #{recent.clock}.") if recent

      refuse(CAPPED) if live.where("created_at > ?", 1.hour.ago).count >= HOURLY_CAP
    end

    def dispatch(access, request)
      answered = false
      owner, repo = access.repository_parts
      inputs = @tags ? { access.tag_input => @tags } : {}
      response = Github::Client.new(access.token).dispatch_workflow(owner, repo, access.workflow, ref: @ref, inputs: inputs)
      answered = true
      settle(access, request, response)
    rescue Github::Client::Error
      # run_tests_ready? and the format checks above vet every part, so only a stored token
      # that fails the client's own check lands here: a bad credential, same copy as a 401.
      # Rejected with no HTTP status marks it, so the panel line shows the same copy.
      request.update_columns(status: "rejected", http_status: nil, message: nil)
      Outcome.new(ok: false, message: COPY.fetch(401), request: request)
    rescue StandardError
      request.update_columns(status: "failed", message: nil) unless answered
      raise
    end

    def settle(access, request, response)
      code = response.status
      status = status_for(code)
      message = response.message && access.redact(response.message)[0, RunRequest::MAX_MESSAGE]
      # update_columns: once GitHub has answered, no validation or callback may change the verdict.
      request.update_columns(status: status, http_status: code.is_a?(Integer) ? code : nil, message: message,
                             github_run_id: response.run_id, html_url: response.html_url)
      Outcome.new(ok: status == "accepted", message: outcome_copy(status, request), request: request)
    end

    def outcome_copy(status, request)
      return "Tests requested on #{@ref}. Results appear in Builds when the run uploads them." if status == "accepted"

      self.class.error_copy(request.http_status, request.message)
    end

    def status_for(code)
      return "failed" unless code.is_a?(Integer)

      if code.between?(200, 299) then "accepted"
      elsif code == 429 || code >= 500 then "failed"
      elsif code.between?(400, 499) then "rejected"
      else "failed"
      end
    end

    def refuse(message) = Outcome.new(ok: false, message: message, request: nil)
  end
end
