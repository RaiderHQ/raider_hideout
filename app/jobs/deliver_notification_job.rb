class DeliverNotificationJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 5

  # Single 5-execution budget, handled here rather than via retry_on so that the
  # Retry-After wait, the backoff and the final "failed" status share one code path.
  def perform(delivery_id)
    delivery = NotificationDelivery.includes(:notification_channel, :build).find_by(id: delivery_id)
    return if delivery.nil? || delivery.status == "sent"

    channel = delivery.notification_channel
    return delivery.update!(status: "failed", last_error: "channel deleted") if channel.nil?
    return delivery.update!(status: "failed", last_error: "channel disabled") unless channel.enabled?
    return skip_without_smtp(delivery, channel) if channel.kind == "email" && !Hideout.mail_enabled?

    delivery.increment!(:attempts)
    # At-least-once: a crash between deliver and the update! below re-sends on the next run.
    begin
      Notifications.notifier_for(channel).deliver(message_for(delivery, channel))
      delivery.update!(status: "sent", sent_at: Time.current, last_error: nil)
    rescue Notifications::RetryableError => e
      handle_retryable(delivery, channel, e)
    rescue Notifications::PermanentError => e
      record_failure(delivery, channel, e, "failed")
    rescue StandardError => e
      delivery.update!(status: "failed",
                       last_error: channel.redact("unexpected #{e.class}: #{e.message}").truncate(500))
      raise
    end
  end

  private

  def skip_without_smtp(delivery, channel)
    Rails.logger.warn("[hideout] email channel #{channel.id} skipped: SMTP_ADDRESS not set")
    delivery.update!(status: "failed", last_error: "skipped: SMTP_ADDRESS not set")
  end

  def handle_retryable(delivery, channel, error)
    if executions >= MAX_ATTEMPTS
      record_failure(delivery, channel, error, "failed")
    else
      record_failure(delivery, channel, error, "pending")
      retry_job(wait: error.retry_after ? error.retry_after.seconds : (executions**4 + 2).seconds)
    end
  end

  def record_failure(delivery, channel, error, status)
    delivery.update!(status: status, last_error: channel.redact(error.message).truncate(500))
  end

  def message_for(delivery, channel)
    options = Rails.application.config.action_mailer.default_url_options || {}
    if delivery.kind == "test"
      Notifications::Message.test(channel, url_options: options)
    else
      Notifications::Message.for_build(delivery.build, delivery.events, url_options: options)
    end
  end
end
