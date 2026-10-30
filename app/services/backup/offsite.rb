require "aws-sdk-s3"
require "storage_service"

# Copies nightly backups to a second bucket with its own key pair, so losing the
# server's disk, or leaking the attachments key, cannot take the backups with it
# (spec 2026-10-21 §4.3).
class Backup
  class Offsite
    PREFIX = "backups/".freeze
    ERRORS = [ Aws::Errors::ServiceError, Seahorse::Client::NetworkingError ].freeze

    def self.enabled?(env = ENV) = env["BACKUP_BUCKET"].to_s.strip.present?

    def self.client(env = ENV)
      Aws::S3::Client.new(**StorageService.backup_options(env))
    end

    def initialize(client: self.class.client, bucket: ENV.fetch("BACKUP_BUCKET"))
      @client = client
      @bucket = bucket
    end

    def upload(path)
      path = Pathname(path)
      File.open(path, "rb") { |file| @client.put_object(bucket: @bucket, key: PREFIX + path.basename.to_s, body: file) }
    rescue *ERRORS => e
      raise Failed, "offsite upload: #{e.message}"
    end

    def rotate
      names = remote_names
      (names - Backup.keep(names)).each { |name| @client.delete_object(bucket: @bucket, key: PREFIX + name) }
    rescue *ERRORS => e
      raise Failed, "offsite rotate: #{e.message}"
    end

    def fetch(name, dir)
      unless Backup::PATTERN.match?(name.to_s)
        raise Failed, "#{name.inspect} is not a backup file name; pass the file name only, like raider-20261020-023000.sqlite3.gz"
      end

      FileUtils.mkdir_p(dir)
      File.chmod(0o700, dir)
      target = Pathname(dir).join(name)
      @client.get_object(bucket: @bucket, key: PREFIX + name, response_target: target.to_s)
      File.chmod(0o600, target)
      target
    rescue *ERRORS => e
      FileUtils.rm_f(target) if target
      raise Failed, "offsite fetch #{name}: #{e.message}"
    end

    private

    def remote_names
      @client.list_objects_v2(bucket: @bucket, prefix: PREFIX).each_page.flat_map(&:contents)
             .map { |object| object.key.delete_prefix(PREFIX) }
             .grep(Backup::PATTERN)
    end
  end
end
