require "storage_service"
require_relative "hideout/settings"
require_relative "hideout/setup_code"

# Fails production boot early, naming every missing setting, instead of
# failing later on the first mail, generated link or upload (spec 2026-10-29 §6, §7).
module ProductionChecks
  class MissingConfiguration < StandardError; end

  REQUIRED = %w[APP_HOST].freeze
  MAIL_REQUIRED = %w[MAILER_FROM].freeze
  S3_REQUIRED = %w[S3_BUCKET S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY].freeze
  BACKUP_REQUIRED = %w[BACKUP_S3_ACCESS_KEY_ID BACKUP_S3_SECRET_ACCESS_KEY].freeze
  SMTP_WARNING = "[hideout] SMTP_ADDRESS is not set; email will not be delivered".freeze
  HTTPS_WARNING = "[hideout] HTTPS is off: tokens and passwords travel in clear text".freeze
  SETUP_CODE_TOO_SHORT = "HIDEOUT_SETUP_CODE must have at least 8 letters or digits".freeze
  OPEN_SIGNUP_NEEDS_SMTP = "HIDEOUT_OPEN_SIGNUP needs SMTP_ADDRESS so new accounts can verify their email".freeze

  def self.enabled?(env, rails_env: Rails.env)
    rails_env.production? && env["SECRET_KEY_BASE_DUMMY"].to_s.strip.empty?
  end

  def self.verify!(env, logger: Rails.logger, err: $stderr)
    problems = required(env).select { |name| StorageService.setting(name, env).empty? }
                            .map { |name| "#{name} is required in production" }
    problems.concat(storage_problems(env))
    problems << OPEN_SIGNUP_NEEDS_SMTP if Hideout.open_signup?(env) && !smtp?(env)
    problems << SETUP_CODE_TOO_SHORT if setup_code_too_short?(env)
    raise MissingConfiguration, problems.join("; ") if problems.any?

    warnings(env).each do |message|
      logger.warn(message)
      err.puts(message)
    end
    true
  end

  def self.warnings(env)
    list = []
    list << SMTP_WARNING unless smtp?(env)
    list << HTTPS_WARNING unless Hideout.force_ssl?(env)
    list << StorageService::DEPRECATION_WARNING if StorageService.deprecated?(env)
    list
  end

  def self.setup_code_too_short?(env)
    raw = env["HIDEOUT_SETUP_CODE"].to_s
    !raw.strip.empty? && Hideout::SetupCode.normalize(raw).count("A-Z0-9") < Hideout::SetupCode::LENGTH
  end

  def self.smtp?(env) = !env["SMTP_ADDRESS"].to_s.strip.empty?

  def self.required(env)
    names = REQUIRED.dup
    names.concat(MAIL_REQUIRED) if smtp?(env)
    names.concat(S3_REQUIRED) if StorageService.s3?(env)
    names.concat(BACKUP_REQUIRED) unless env["BACKUP_BUCKET"].to_s.strip.empty?
    names.uniq
  end

  # Backups only on AWS: the offsite client would sign for region "auto" and fail at 02:30.
  def self.backup_region_missing?(env)
    return false if env["BACKUP_BUCKET"].to_s.strip.empty?

    options = StorageService.backup_options(env)
    !options.key?(:endpoint) && options[:region] == "auto"
  end

  def self.storage_problems(env)
    problems = []
    unless StorageService.known_service?(env)
      problems << "ACTIVE_STORAGE_SERVICE must be one of: #{StorageService::SERVICES.join(', ')} (got #{StorageService.service(env)})"
    end
    endpoint = StorageService.setting("S3_ENDPOINT", env)
    if !endpoint.empty? && !StorageService.valid_endpoint?(endpoint)
      problems << "S3_ENDPOINT must be an http(s) URL with no path, like https://<account>.r2.cloudflarestorage.com (got #{endpoint})"
    end
    if StorageService.s3?(env) && endpoint.empty? && StorageService.region(env) == "auto"
      problems << "S3_REGION must be set to your bucket's AWS region when S3_ENDPOINT is empty"
    elsif backup_region_missing?(env)
      problems << "BACKUP_S3_REGION (or S3_REGION) must be set to the backup bucket's AWS region " \
                  "when BACKUP_S3_ENDPOINT and S3_ENDPOINT are empty"
    end
    problems
  end
end
