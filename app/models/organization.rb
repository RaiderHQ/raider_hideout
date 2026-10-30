class Organization < ApplicationRecord
  include Sluggable

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :projects, dependent: :destroy
  has_many :invitations, dependent: :destroy
  belongs_to :personal_owner, class_name: "User", optional: true, inverse_of: :personal_organization

  validates :name, presence: true, length: { maximum: 100 }
  validates :personal_owner_id, uniqueness: true, allow_nil: true

  PERSONAL_SUFFIX = "'s organization".freeze

  def self.create_personal!(user)
    transaction do
      create!(name: personal_name_for(user), personal: true, personal_owner: user)
        .tap { |organization| organization.memberships.create!(user: user, role: "owner") }
    end
  end

  # The email local part, truncated so the name fits the 100-char limit.
  def self.personal_name_for(user)
    local = user.email_address.to_s.split("@").first.to_s
    "#{local.first(100 - PERSONAL_SUFFIX.length)}#{PERSONAL_SUFFIX}"
  end

  def role_for(user)
    return nil unless user

    memberships.find_by(user_id: user.id)&.role
  end

  def owners
    users.where(memberships: { role: "owner" })
  end

  def notification_recipients
    users.where(memberships: { role: %w[owner admin] }).order(:id).pluck(:email_address)
  end
end
