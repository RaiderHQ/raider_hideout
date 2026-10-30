class NotifyBuildJob < ApplicationJob
  queue_as :default

  def perform(build_id)
    build = Build.find_by(id: build_id)
    return unless build&.ready_to_notify?

    build.project.notification_channels.where(enabled: true).find_each do |channel|
      next unless Notifications::BranchFilter.match?(channel, build)

      events = Notifications::Rules.call(channel, build)
      next if events.empty?

      delivery = channel.notification_deliveries.create!(kind: "build", build: build, events: events)
      DeliverNotificationJob.perform_later(delivery.id)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end
end
