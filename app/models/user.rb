class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :saved_views, dependent: :delete_all
  has_many :personal_tokens, dependent: :delete_all
  has_many :organizations, through: :memberships
  has_one :personal_organization, class_name: "Organization", foreign_key: :personal_owner_id,
                                  inverse_of: :personal_owner, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true

  generates_token_for :email_verification, expires_in: 24.hours do
    # email_verified_at makes the link single-use: it stops matching once verified.
    [ email_address, email_verified_at.to_s ]
  end

  def verified? = email_verified_at.present?

  def verify_email!
    update!(email_verified_at: Time.current) unless verified?
  end

  def projects
    Project.where(organization_id: memberships.select(:organization_id))
  end

  def role_in(organization)
    memberships.find_by(organization_id: organization.id)&.role
  end
end
