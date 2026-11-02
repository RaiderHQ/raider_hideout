class NotifyBuildJob < ApplicationJob
  queue_as :default

  def perform(build_id, attempt = 1)
    build = Build.find_by(id: build_id)
    return unless build&.attempt_ready?(attempt)

    if build.rerun_attempt?(attempt)
      Builds::Baseline.assign!(build)
      Builds::Gate.evaluate!(build, attempt: attempt)
      if build.notification_deliveries.where(kind: "build", attempt: attempt).exists?
        Rails.logger.info("[notify] build #{build.id} attempt #{attempt}: late run after announcement, no new delivery")
      end
    end

    build.project.notification_channels.where(enabled: true).find_each do |channel|
      next unless Notifications::BranchFilter.match?(channel, build)

      events = Notifications::Rules.call(channel, build, attempt: attempt)
      next if events.empty?

      delivery = channel.notification_deliveries.create!(kind: "build", build: build, attempt: attempt, events: events)
      DeliverNotificationJob.perform_later(delivery.id)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end
end
