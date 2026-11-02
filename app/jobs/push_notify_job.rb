# Fans a finished build out to subscribed phones. One PushDelivery row per subscription,
# build and attempt is the dedup; each device then gets its own PushSendJob so a slow or
# throttled push service retries only that device.
class PushNotifyJob < ApplicationJob
  queue_as :default

  def perform(build_id, attempt = 1)
    build = Build.find_by(id: build_id)
    return unless build

    Push::Recipients.call(build).each do |subscription, events|
      delivery = PushDelivery.create!(push_subscription: subscription, build: build, attempt: attempt)
      PushSendJob.perform_later(delivery.id, events)
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end
end
