class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user

  # Pages read the user from the session; a personal API token sets it directly (spec §4.3).
  def user = super || session&.user
end
