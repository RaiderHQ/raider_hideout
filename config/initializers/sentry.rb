# Error tracking, on only when SENTRY_DSN is set (spec 2026-10-29 §7.2). Any region works; the scrubber removes personal data.
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    config.dsn = ENV["SENTRY_DSN"]
    config.environment = Rails.env
    config.release = ENV["KAMAL_VERSION"].presence
    config.send_default_pii = false
    config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", "0").to_f
    config.before_send = ->(event, hint) { SentryScrubber.call(event, hint) }
  end
end
