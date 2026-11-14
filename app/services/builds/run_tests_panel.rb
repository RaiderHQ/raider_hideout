module Builds
  # Which Run tests control a viewer sees on the project page and the builds list.
  class RunTestsPanel
    def initialize(project, role_at_least:)
      @project = project
      @role_at_least = role_at_least
    end

    # :button (member+, set up), :set_up (admin+, not set up), :ask_admin (member) or nil (viewer).
    def state
      return unless @role_at_least.call(:member)
      return :button if @project.ci_access&.run_tests_ready?

      @role_at_least.call(:admin) ? :set_up : :ask_admin
    end
  end
end
