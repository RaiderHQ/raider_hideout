# A user's read-only token for the public API and MCP (spec §4.1). Only the SHA-256 digest
# and the first 8 characters are stored; revoking keeps the row.
class PersonalToken < ApplicationRecord
  PREFIX = "rdp_".freeze
  EXPIRY_DAYS = [ 30, 90, 365, nil ].freeze
  DEFAULT_EXPIRY_DAYS = 90
  MAX_ACTIVE = 20
  DISPLAY_PREFIX_LENGTH = 8
  LAST_USED_EVERY = 1.minute

  belongs_to :user

  # The issue-time choice; validated on create, never stored.
  attr_accessor :expires_in_days

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 100 }
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validate :expiry_is_a_choice, :name_unique_among_active, :within_active_limit, on: :create

  scope :active, ->(now = Time.current) {
    where(revoked_at: nil).where("personal_tokens.expires_at IS NULL OR personal_tokens.expires_at > ?", now)
  }

  def self.digest(plain)
    OpenSSL::Digest::SHA256.hexdigest(plain)
  end

  def self.issue!(user:, name:, expires_in_days:, now: Time.current)
    plain = PREFIX + SecureRandom.base58(32)
    token = new(user: user, name: name, token_digest: digest(plain), token_prefix: plain.first(DISPLAY_PREFIX_LENGTH))
    token.expires_in_days = expires_in_days
    token.expires_at = now + expires_in_days.days if expires_in_days.is_a?(Integer) && EXPIRY_DAYS.include?(expires_in_days)
    token.save!
    [ token, plain ]
  end

  # Project (rdr_) tokens never match here, whatever their digest.
  def self.authenticate(plain, now: Time.current)
    return nil unless plain.is_a?(String) && plain.start_with?(PREFIX)

    token = active(now).find_by(token_digest: digest(plain))
    return nil unless token

    token.update_column(:last_used_at, now) if token.last_used_at.nil? || token.last_used_at < now - LAST_USED_EVERY
    token
  end

  def revoke!(now: Time.current)
    update!(revoked_at: now) unless revoked_at
    self
  end

  def status(now = Time.current)
    return "revoked" if revoked_at
    return "expired" if expires_at && expires_at <= now

    "active"
  end

  private

  def expiry_is_a_choice
    errors.add(:base, "Expiry must be 30, 90 or 365 days, or never") unless expiry_choice?
  end

  # Integers only: 30.0 == 30, but the setter in issue! skips a Float and would mint a permanent token.
  def expiry_choice?
    expires_in_days.nil? || (expires_in_days.is_a?(Integer) && EXPIRY_DAYS.include?(expires_in_days))
  end

  def name_unique_among_active
    return if user.nil? || name.blank?

    errors.add(:name, "is already used by one of your active tokens") if user.personal_tokens.active.where(name: name).exists?
  end

  def within_active_limit
    return if user.nil?

    errors.add(:base, "You already have #{MAX_ACTIVE} active tokens; revoke one first") if user.personal_tokens.active.count >= MAX_ACTIVE
  end
end
