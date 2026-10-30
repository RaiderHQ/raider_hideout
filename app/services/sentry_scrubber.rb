# Sentry before_send hook (spec 2026-10-21 §4.4). Ingest bodies hold customers'
# test names and messages, Authorization holds API tokens and Cookie the session,
# Referer can carry password-reset or invitation token URLs; none of them leave the server. Not under the gem's Sentry namespace on purpose.
module SentryScrubber
  DROPPED_HEADERS = %w[authorization cookie referer].freeze

  def self.call(event, _hint)
    request = event.request
    return event unless request

    request.headers = request.headers&.reject { |name, _| DROPPED_HEADERS.include?(name.to_s.downcase) }
    request.data = nil
    request.cookies = nil
    event
  end
end
