# Creates the first admin, their personal and team organizations, the first
# project and its CI token in one transaction (spec 2026-10-29 §5.3). Shared
# by /setup and bin/rails hideout:setup.
class InstanceSetup
  include ActiveModel::Model
  include ActiveModel::Attributes

  class AlreadyDone < StandardError; end
  Result = Data.define(:user, :organization, :project, :token)

  attribute :email_address, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :organization_name, :string
  attribute :project_name, :string

  validates :organization_name, :project_name, presence: true
  validates :organization_name, length: { maximum: 100 }

  def self.pending? = !User.exists?

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      lock_users!
      raise AlreadyDone if User.exists?

      create_everything
    end
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.full_messages.each { |message| errors.add(:base, message) }
    false
  end

  private

  # SQLite transactions are IMMEDIATE, so setups already run one at a time.
  # On Postgres this lock conflicts with itself: a second setup waits, then sees the first user.
  def lock_users!
    # The connection the surrounding transaction holds, so the lock lasts until it commits.
    connection = ActiveRecord::Base.lease_connection
    connection.execute("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE") if connection.adapter_name.match?(/postg/i)
  end

  def create_everything
    user = User.create!(email_address: email_address, password: password,
                        password_confirmation: password_confirmation, email_verified_at: Time.current)
    Organization.create_personal!(user)
    organization = Organization.create!(name: organization_name.strip)
    organization.memberships.create!(user: user, role: "owner")
    project = organization.projects.create!(name: project_name.strip)
    _token, plaintext = ApiToken.issue!(project: project, name: "CI")
    Result.new(user: user, organization: organization, project: project, token: plaintext)
  end
end
