# Prints the first-run setup link when a server boots with no users (spec 2026-10-29 §5.2).
# Only for `bin/rails server`: a rake task or console would print a code that this server never accepts.
Rails.application.config.after_initialize do
  next unless defined?(Rails::Server)

  pending = begin
    InstanceSetup.pending?
  rescue ActiveRecord::ActiveRecordError
    false
  end
  next unless pending

  message = Hideout::SetupCode.announcement
  Rails.logger.info(message)
  $stderr.puts(message)
end
