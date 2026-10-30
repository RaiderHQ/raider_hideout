require "uri"

# Which Active Storage service production uses, and its S3 settings
# (spec 2026-10-29 §7.2). The r2 service and the R2_* names are deprecated
# aliases kept for one release.
module StorageService
  SERVICES = %w[local s3].freeze
  DEPRECATED_SERVICE = "r2".freeze
  FALLBACKS = {
    "S3_ENDPOINT" => "R2_ENDPOINT",
    "S3_BUCKET" => "R2_BUCKET",
    "S3_ACCESS_KEY_ID" => "R2_ACCESS_KEY_ID",
    "S3_SECRET_ACCESS_KEY" => "R2_SECRET_ACCESS_KEY",
    "BACKUP_S3_ACCESS_KEY_ID" => "BACKUP_ACCESS_KEY_ID",
    "BACKUP_S3_SECRET_ACCESS_KEY" => "BACKUP_SECRET_ACCESS_KEY"
  }.freeze
  DEPRECATION_WARNING = "[hideout] R2_* settings are deprecated; rename them to S3_*".freeze
  TRUE_VALUES = %w[true 1 yes].freeze

  def self.service(env = ENV)
    value = env["ACTIVE_STORAGE_SERVICE"].to_s.strip
    value.empty? ? "local" : value
  end

  def self.s3?(env = ENV) = [ "s3", DEPRECATED_SERVICE ].include?(service(env))

  def self.known_service?(env = ENV) = s3?(env) || service(env) == "local"

  def self.setting(name, env = ENV)
    value = env[name].to_s.strip
    return value unless value.empty?

    FALLBACKS.key?(name) ? env[FALLBACKS[name]].to_s.strip : ""
  end

  def self.deprecated?(env = ENV)
    service(env) == DEPRECATED_SERVICE || FALLBACKS.values.any? { |name| !env[name].to_s.strip.empty? }
  end

  # R2 needed path-style addressing before the rename, so the r2 alias keeps it.
  def self.path_style?(env = ENV)
    value = env["S3_FORCE_PATH_STYLE"].to_s.strip.downcase
    value.empty? ? service(env) == DEPRECATED_SERVICE : TRUE_VALUES.include?(value)
  end

  def self.region(env = ENV)
    value = setting("S3_REGION", env)
    value.empty? ? "auto" : value
  end

  # The S3 entries of config/storage.yml. No endpoint means AWS.
  def self.s3_options(env = ENV)
    options = { region: region(env), bucket: setting("S3_BUCKET", env), access_key_id: setting("S3_ACCESS_KEY_ID", env),
                secret_access_key: setting("S3_SECRET_ACCESS_KEY", env), force_path_style: path_style?(env) }
    endpoint = setting("S3_ENDPOINT", env)
    endpoint.empty? ? options : options.merge(endpoint: endpoint)
  end

  # The offsite backup client: its own key pair, and the attachments endpoint
  # and region unless BACKUP_S3_ENDPOINT / BACKUP_S3_REGION are set.
  def self.backup_options(env = ENV)
    endpoint = setting("BACKUP_S3_ENDPOINT", env)
    endpoint = setting("S3_ENDPOINT", env) if endpoint.empty?
    backup_region = setting("BACKUP_S3_REGION", env)
    backup_region = region(env) if backup_region.empty?
    options = { region: backup_region, force_path_style: path_style?(env),
                access_key_id: setting("BACKUP_S3_ACCESS_KEY_ID", env),
                secret_access_key: setting("BACKUP_S3_SECRET_ACCESS_KEY", env) }
    endpoint.empty? ? options : options.merge(endpoint: endpoint)
  end

  # The browser origin of presigned attachment URLs, for the CSP. Asks the SDK
  # rather than building it: AWS us-east-1 presigns on <bucket>.s3.amazonaws.com.
  def self.s3_origin(env = ENV)
    return unless s3?(env)

    require "aws-sdk-s3"
    options = s3_options(env)
    client = Aws::S3::Client.new(**options.except(:bucket), stub_responses: true)
    bucket = options[:bucket].empty? ? "bucket" : options[:bucket]
    uri = URI.parse(Aws::S3::Object.new(bucket, "probe", client: client).presigned_url(:get))
    port = uri.port == uri.default_port ? "" : ":#{uri.port}"
    "#{uri.scheme}://#{uri.host}#{port}"
  rescue URI::InvalidURIError, ArgumentError, Aws::Errors::ServiceError
    nil
  end

  # An account endpoint: http(s), a host, and nothing after it (no bucket path).
  def self.valid_endpoint?(value)
    uri = parse_endpoint(value)
    !uri.nil? && [ "", "/" ].include?(uri.path.to_s) && uri.query.nil? && uri.fragment.nil?
  end

  def self.parse_endpoint(value)
    uri = URI.parse(value.to_s.strip)
    uri if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    nil
  end
  private_class_method :parse_endpoint
end
