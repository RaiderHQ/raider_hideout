# Instance settings read from the environment (spec 2026-10-29 §4.3, §6, §7.1).
# Loaded from config/application.rb before the app boots.
module Hideout
  TRUE_VALUES = %w[true 1 yes].freeze
  FALSE_VALUES = %w[false 0 no].freeze

  # Sent on every response, static files included. The app uses none of these browser features;
  # the clipboard (copy buttons) is deliberately not listed.
  PERMISSIONS_POLICY = %w[camera microphone geolocation usb payment gyroscope magnetometer accelerometer].map { |f| "#{f}=()" }.join(", ").freeze

  def self.flag(env, name) = env[name].to_s.strip.downcase

  def self.open_signup?(env = ENV) = TRUE_VALUES.include?(flag(env, "HIDEOUT_OPEN_SIGNUP"))

  def self.force_ssl?(env = ENV) = !FALSE_VALUES.include?(flag(env, "HIDEOUT_FORCE_SSL"))

  # Only for TLS proxies that send no X-Forwarded-Proto: with it on, plain HTTP counts as HTTPS.
  def self.assume_ssl?(env = ENV) = TRUE_VALUES.include?(flag(env, "HIDEOUT_ASSUME_SSL"))

  def self.url_protocol(env = ENV) = force_ssl?(env) ? "https" : "http"

  # Production follows SMTP_ADDRESS; development and test always have a mailer.
  def self.mail_enabled?(env = ENV, rails_env: Rails.env)
    return true unless rails_env.to_s == "production"

    !env["SMTP_ADDRESS"].to_s.strip.empty?
  end

  # APP_HOST may carry a port (localhost:3010); host authorization wants the name alone.
  def self.host_name(env = ENV) = env["APP_HOST"].to_s.strip.sub(/:\d+\z/, "")

  # What RAIDER_ENDPOINT should be set to.
  def self.base_url(env = ENV, rails_env: Rails.env)
    host = env["APP_HOST"].to_s.strip
    port = env["PORT"].to_s.strip
    host = "localhost:#{port.empty? ? 3000 : port}" if host.empty?
    protocol = rails_env.to_s == "production" ? url_protocol(env) : "http"
    "#{protocol}://#{host}"
  end
end
