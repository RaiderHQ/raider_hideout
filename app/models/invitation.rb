class Invitation < ApplicationRecord
  ROLES = %w[admin member viewer].freeze
  LIFETIME = 7.days

  # Raised when an invitation can't be issued or accepted; the message is user-facing copy.
  class NotIssuable < StandardError; end
  class NotAcceptable < StandardError; end

  # The raw token is kept encrypted so the mail job can read it when it runs.
  encrypts :token

  belongs_to :organization
  belongs_to :invited_by, class_name: "User"

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :role_allowed
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :outstanding, -> { where(accepted_at: nil, revoked_at: nil) }
  scope :pending, -> { outstanding.where(arel_table[:expires_at].gt(Time.current)) }

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token)
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  # Returns [invitation, raw_token]. The digest is the lookup key; the raw token is kept
  # encrypted for the mail job, and cleared once the invite is used or revoked.
  #
  # Raises NotIssuable when the email already belongs to a member or has a
  # pending invitation. Expired-but-open rows for the same email are revoked
  # first: the partial unique index ignores expires_at, so they would
  # otherwise block a fresh invite forever.
  def self.issue!(organization:, email:, role:, invited_by:)
    email = normalize_value_for(:email, email.to_s)
    raw_token = generate_token
    invitation = transaction do
      if organization.users.exists?(email_address: email)
        raise NotIssuable, "#{email} is already a member"
      end

      existing = organization.invitations.outstanding.where(email: email)
      existing.where(arel_table[:expires_at].lteq(Time.current)).update_all(revoked_at: Time.current, token: nil, updated_at: Time.current)
      raise NotIssuable, pending_message(email) if existing.exists?

      create!(organization: organization, email: email, role: role, invited_by: invited_by,
              token_digest: digest(raw_token), token: raw_token, expires_at: LIFETIME.from_now)
    end
    [ invitation, raw_token ]
  rescue ActiveRecord::RecordNotUnique
    # A concurrent issue! won the partial unique index.
    raise NotIssuable, pending_message(email)
  end

  def self.pending_message(email)
    "#{email} already has a pending invitation — resend it instead"
  end
  private_class_method :pending_message

  def self.find_by_token(raw_token)
    return nil if raw_token.blank?

    find_by(token_digest: digest(raw_token.to_s))
  end

  def reissue!
    raw_token = self.class.generate_token
    update!(token: raw_token, token_digest: self.class.digest(raw_token), expires_at: LIFETIME.from_now)
    raw_token
  end

  def pending?
    accepted_at.nil? && revoked_at.nil? && expires_at.future?
  end

  def revoke!
    update!(revoked_at: Time.current, token: nil)
  end

  def role_allowed
    errors.add(:base, "Invitations can be for admin, member or viewer") unless ROLES.include?(role)
  end
  private :role_allowed

  def for?(user)
    user.present? && user.email_address.to_s.casecmp?(email)
  end

  # Joins +user+ to the organization with the invite's role (an existing
  # member keeps their role) and marks the invite accepted, atomically: the
  # conditional UPDATE means two concurrent accepts can't both succeed.
  def accept!(user)
    raise NotAcceptable, "This invitation is no longer valid. Ask an admin to send a new one." unless pending?
    raise NotAcceptable, "Use the invited email address" unless for?(user)

    transaction do
      now = Time.current
      claimed = self.class.pending.where(id: id).update_all(accepted_at: now, token: nil, updated_at: now)
      raise NotAcceptable, "This invitation is no longer valid. Ask an admin to send a new one." unless claimed == 1

      organization.memberships.find_or_create_by!(user: user) { |membership| membership.role = role }
    end
    reload
  end
end
