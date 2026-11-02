module Builds
  # What the re-run UI shows for one build and one viewer, worked out once so the page and its
  # failed-test cards share the answer instead of each asking the database again.
  class RerunPanel
    RECORD_LIMIT = 5

    # `role_at_least` is asked only when the build is a re-run candidate, so other pages pay
    # no role lookup for it.
    def initialize(build, role_at_least:)
      @build = build
      @role_at_least = role_at_least
    end

    # :button, :pending, :add_token (admin link), :ask_admin (member text) or nil.
    def state
      return @state if defined?(@state)

      @state = compute_state
    end

    def button? = state == :button

    def pending = (state; @pending)

    def records
      return [] unless @build.provider == "github_actions"

      @records ||= @build.reruns.includes(:user).order(created_at: :desc, id: :desc).limit(RECORD_LIMIT).to_a
    end

    private

    def compute_state
      return unless @build.rerun_candidate? && @role_at_least.call(:member)
      return (@role_at_least.call(:admin) ? :add_token : :ask_admin) unless @build.project.ci_access

      @pending = @build.pending_rerun
      @pending ? :pending : :button
    end
  end
end
