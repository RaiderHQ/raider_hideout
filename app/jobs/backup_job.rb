class BackupJob < ApplicationJob
  queue_as :default

  # Alerts when the nightly backup fails or never runs (inert without SENTRY_DSN).
  include Sentry::Cron::MonitorCheckIns
  sentry_monitor_check_ins slug: "backup-job",
                           monitor_config: Sentry::Cron::MonitorConfig.from_crontab("30 2 * * *", timezone: "UTC")

  def perform
    path = Backup.new.create
    return unless path

    Rails.logger.info("[backup] wrote #{path} (#{ActiveSupport::NumberHelper.number_to_human_size(File.size(path))})")
    return unless Backup::Offsite.enabled?

    offsite = Backup::Offsite.new
    offsite.upload(path)
    offsite.rotate
    Rails.logger.info("[backup] copied #{Pathname(path).basename} offsite")
  end
end
