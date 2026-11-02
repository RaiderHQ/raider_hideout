# POSTs one push to one subscription. The endpoint is user-registered, so it is re-checked
# against the allowlist here, redirects are never followed (web-push's Net::HTTP does not),
# and nothing that identifies the endpoint, keys or payload is logged: only record ids.
class PushSendJob < ApplicationJob
  queue_as :default

  TIMEOUT = 10
  NETWORK_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError ].freeze

  # Raised in place of web-push / network errors, whose messages carry the endpoint host and response body.
  class TemporaryFailure < StandardError; end

  retry_on TemporaryFailure, wait: :polynomially_longer, attempts: 5 do |job, _error|
    Rails.logger.warn("[push] delivery #{job.arguments.first}: giving up after repeated temporary failures")
  end

  def perform(delivery_id, events)
    delivery = PushDelivery.find_by(id: delivery_id)
    return unless delivery

    subscription = delivery.push_subscription
    unless PushSubscription.allowed_endpoint?(subscription.endpoint)
      Rails.logger.warn("[push] subscription #{subscription.id}: endpoint no longer allowed, skipped")
      return
    end

    message = Push::Payload.for(delivery.build, events, attempt: delivery.attempt).to_json
    deliver(subscription, delivery, message)
  end

  private

  def deliver(subscription, delivery, message)
    vapid = VapidKey.current
    WebPush.payload_send(
      message: message, endpoint: subscription.endpoint, p256dh: subscription.p256dh, auth: subscription.auth,
      vapid: { subject: vapid.subject, public_key: vapid.public_key, private_key: vapid.private_key },
      ttl: 24.hours.to_i, urgency: "high", open_timeout: TIMEOUT, read_timeout: TIMEOUT, ssl_timeout: TIMEOUT
    )
    subscription.update_column(:last_success_at, Time.current)
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription
    subscription.destroy
  rescue WebPush::Unauthorized
    Rails.logger.error("[push] subscription #{subscription.id} delivery #{delivery.id}: push service rejected our VAPID credentials")
  rescue WebPush::PayloadTooLarge
    Rails.logger.error("[push] subscription #{subscription.id} delivery #{delivery.id}: payload too large")
  rescue WebPush::TooManyRequests, WebPush::PushServiceError
    raise TemporaryFailure
  rescue WebPush::ResponseError => e
    Rails.logger.error("[push] subscription #{subscription.id} delivery #{delivery.id}: unexpected response #{e.response.code}")
  rescue *NETWORK_ERRORS
    raise TemporaryFailure
  end
end
