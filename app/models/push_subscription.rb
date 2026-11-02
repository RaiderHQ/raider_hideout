# One browser/device a user turned phone notifications on for. The server later POSTs to
# `endpoint`, and any signed-in user (even a viewer) registers it, so the endpoint is
# allowlisted to the browsers' push services (SSRF guard).
class PushSubscription < ApplicationRecord
  ALLOWED_HOSTS = %w[fcm.googleapis.com *.push.apple.com updates.push.services.mozilla.com *.notify.windows.com].freeze
  EXTRA_HOSTS_ENV = "HIDEOUT_PUSH_HOSTS".freeze
  MAX_ENDPOINT_LENGTH = 2000
  MAX_LABEL_LENGTH = 60
  BASE64URL = /\A[A-Za-z0-9_-]+={0,2}\z/

  belongs_to :user

  validates :endpoint, presence: true, length: { maximum: MAX_ENDPOINT_LENGTH }
  validates :endpoint, uniqueness: true
  validate :endpoint_host_allowed
  validate :keys_well_formed
  validates :device_label, length: { maximum: MAX_LABEL_LENGTH }

  class << self
    def allowed_endpoint?(url)
      uri = URI.parse(url.to_s)
      return false unless uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && uri.port == 443

      host = uri.host.to_s.downcase.delete_suffix(".")
      return false if host.empty? || ip_literal?(host)

      allowed_hosts.any? { |pattern| host_matches?(host, pattern) }
    rescue URI::InvalidURIError
      false
    end

    def label_from_user_agent(user_agent)
      case user_agent.to_s
      when /iPhone/ then "iPhone"
      when /iPad/ then "iPad"
      when /Android/ then "Android"
      when /Macintosh/ then "Mac"
      else "Browser"
      end
    end

    private

    def allowed_hosts
      extra = ENV[EXTRA_HOSTS_ENV].to_s.split(",").map { _1.strip.downcase }.reject(&:empty?)
      ALLOWED_HOSTS + extra
    end

    def host_matches?(host, pattern)
      if pattern.start_with?("*.")
        host.end_with?(pattern.delete_prefix("*"))
      else
        host == pattern
      end
    end

    def ip_literal?(host)
      bare = host.delete_prefix("[").delete_suffix("]")
      IPAddr.new(bare)
      true
    rescue IPAddr::Error
      host.match?(/\A[\d.]+\z/) # decimal-looking hosts are never push services
    end
  end

  private

  def endpoint_host_allowed
    return if endpoint.blank? || endpoint.length > MAX_ENDPOINT_LENGTH

    errors.add(:endpoint, "is not a supported push service") unless self.class.allowed_endpoint?(endpoint)
  end

  def keys_well_formed
    errors.add(:p256dh, "is not a valid public key") unless decoded_length(p256dh) == 65
    errors.add(:auth, "is not a valid auth secret") unless decoded_length(auth) == 16
  end

  def decoded_length(value)
    return nil unless value.is_a?(String) && value.match?(BASE64URL)

    Base64.urlsafe_decode64(value).bytesize
  rescue ArgumentError
    nil
  end
end
