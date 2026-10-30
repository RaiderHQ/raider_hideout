class NotificationDelivery < ApplicationRecord
  STATUSES = %w[pending sent failed].freeze
  KINDS = %w[build test].freeze

  belongs_to :notification_channel
  belongs_to :build, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
end
