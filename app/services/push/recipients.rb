module Push
  # Who gets a phone push for this build, and for which events. Recipients are the
  # current members of the build's organization, so a removed user never gets a push
  # even if their subscription row survives.
  module Recipients
    # Returns Array<[PushSubscription, Array<String>]>; users with no matching event are left out.
    def self.call(build, attempt: 1)
      project = build.project
      user_ids = Membership.where(organization_id: project.organization_id).select(:user_id)
      subscriptions = PushSubscription.where(user_id: user_ids).order(:id).to_a
      return [] if subscriptions.empty?

      user_ids = subscriptions.map(&:user_id).uniq
      muted = PushMutedProject.where(user_id: user_ids, project_id: project.id).pluck(:user_id).to_set
      preferences = PushPreference.where(user_id: user_ids).index_by(&:user_id)
      facts = Facts.new(build, project, attempt)

      events_by_user = user_ids.index_by(&:itself).transform_values do |user_id|
        muted.include?(user_id) ? [] : facts.events_for(user_id, preferences[user_id] || PushPreference.new)
      end

      subscriptions.filter_map do |subscription|
        events = events_by_user.fetch(subscription.user_id)
        [ subscription, events ] if events.any?
      end
    end

    # Build-level facts, each computed at most once however many users there are.
    class Facts
      def initialize(build, project, attempt)
        @build = build
        @project = project
        @attempt = attempt
      end

      def events_for(user_id, preference)
        events = []
        events << "rerun_result" if preference.rerun_results && rerun_starter_ids.include?(user_id)
        events << "failed" if preference.default_branch_failures && default_branch_failure?
        events << "new_flaky" if preference.new_flaky && new_flaky?
        events << "gate_failed" if preference.gate_failures && gate_failed?
        events
      end

      private

      # Users whose accepted re-run request on this build preceded this attempt.
      def rerun_starter_ids
        @rerun_starter_ids ||=
          if @build.rerun_attempt?(@attempt)
            BuildRerun.where(build_id: @build.id, status: "accepted", attempt_before: ...@attempt).where.not(user_id: nil).pluck(:user_id).to_set
          else
            Set.new
          end
      end

      def default_branch_failure?
        return @default_branch_failure if defined?(@default_branch_failure)

        @default_branch_failure = @build.status == "failed" && @build.branch == @project.default_branch
      end

      def new_flaky?
        return @new_flaky if defined?(@new_flaky)

        @new_flaky = Notifications::Rules.new_flaky?(@build)
      end

      def gate_failed? = @build.gate_status == "failed"
    end
  end
end
