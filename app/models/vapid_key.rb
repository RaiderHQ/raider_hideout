# Application server identity for web push. Generated on first use and stored
# encrypted; never rotated automatically (see hideout:vapid:rotate).
# HIDEOUT_VAPID_PUBLIC_KEY + HIDEOUT_VAPID_PRIVATE_KEY (both or neither) override the stored pair.
class VapidKey < ApplicationRecord
  class Misconfigured < StandardError; end

  Pair = Data.define(:public_key, :private_key, :subject)

  NAME = "default".freeze
  PUBLIC_ENV = "HIDEOUT_VAPID_PUBLIC_KEY".freeze
  PRIVATE_ENV = "HIDEOUT_VAPID_PRIVATE_KEY".freeze
  SUBJECT_ENV = "HIDEOUT_VAPID_SUBJECT".freeze
  FALLBACK_SUBJECT = "https://github.com/RaiderHQ/raider_hideout".freeze

  encrypts :private_key

  class << self
    def current
      env_pair || stored_pair
    end

    # Replaces the stored pair. Returns the number of subscriptions deleted.
    def rotate!
      transaction do
        fresh = WebPush.generate_key
        record = find_by(name: NAME)
        attrs = { public_key: fresh.public_key, private_key: fresh.private_key }
        record ? record.update!(attrs) : create!(attrs.merge(name: NAME))
        0
      end
    end

    private

    def env_pair
      public_key = ENV[PUBLIC_ENV].presence
      private_key = ENV[PRIVATE_ENV].presence
      return nil if public_key.nil? && private_key.nil?
      raise Misconfigured, "#{PRIVATE_ENV} is not set (it must be set together with #{PUBLIC_ENV})" if private_key.nil?
      raise Misconfigured, "#{PUBLIC_ENV} is not set (it must be set together with #{PRIVATE_ENV})" if public_key.nil?

      Pair.new(public_key:, private_key:, subject: subject)
    end

    def stored_pair
      record = find_by(name: NAME) || begin
        fresh = WebPush.generate_key
        create_or_find_by!(name: NAME) do |new_record|
          new_record.public_key = fresh.public_key
          new_record.private_key = fresh.private_key
        end
      end
      Pair.new(public_key: record.public_key, private_key: record.private_key, subject: subject)
    end

    def subject
      ENV[SUBJECT_ENV].presence || owner_subject || FALLBACK_SUBJECT
    end

    def owner_subject
      owner = Membership.where(role: "owner").includes(:user).order(:created_at, :id).first
      "mailto:#{owner.user.email_address}" if owner
    end
  end
end
