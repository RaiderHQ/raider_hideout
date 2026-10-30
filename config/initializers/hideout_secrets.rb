# Refuses keys generated on this boot when the database already has users
# (plan 2026-10-29, Review Focus 3).
Rails.application.config.after_initialize do
  next if Hideout::Secrets.generated.to_a.empty?

  # No database or no users table yet (db:prepare on a fresh install) counts as
  # fresh; any other database error means we cannot tell, so the keys are not kept.
  has_users = begin
    ActiveRecord::Base.with_connection { |connection| connection.table_exists?("users") ? User.exists? : false }
  rescue ActiveRecord::NoDatabaseError
    false
  rescue ActiveRecord::ActiveRecordError
    :unknown
  end
  Hideout::Secrets.check_existing_data!(has_users: has_users)
end
