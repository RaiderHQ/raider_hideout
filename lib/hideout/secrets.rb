require "fileutils"
require "securerandom"
require "yaml"

module Hideout
  # SECRET_KEY_BASE and the Active Record encryption keys come from the
  # environment, then the secrets file, then (production only) fresh random
  # values written to that file (spec 2026-10-29 §5.1).
  module Secrets
    class Unreadable < StandardError; end

    NAMES = %w[
      SECRET_KEY_BASE
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    ].freeze
    DEFAULT_FILE = "storage/hideout-secrets.yml".freeze

    class << self
      attr_reader :generated, :path

      def load!(root:, rails_env:, env: ENV, err: $stderr)
        @generated = []
        @previous = nil
        return @generated unless rails_env.to_s == "production"
        return @generated unless env["SECRET_KEY_BASE_DUMMY"].to_s.strip.empty?

        missing = NAMES.select { |name| blank?(env[name]) }
        return @generated if missing.empty?

        @path = path_for(env, root)
        # Two processes booting on an empty volume must not both generate keys.
        with_lock(@path) do
          stored = read(@path)
          # Keys from an earlier boot that never reached the users check (it failed
          # first) stay unconfirmed until a boot sees an empty database.
          unconfirmed = read_unconfirmed
          @previous = unconfirmed ? unconfirmed["previous"] : (stored.dup if File.exist?(@path))
          fresh = missing.select { |name| blank?(stored[name]) }
          @generated = (missing & unconfirmed.to_h.fetch("generated", [])) | fresh
          unless @generated.empty?
            # The marker goes first: a crash between the writes must not leave unmarked keys.
            write(unconfirmed_path, { "generated" => @generated, "previous" => @previous })
          end
          unless fresh.empty?
            stored = stored.merge(fresh.to_h { |name| [ name, generate(name) ] })
            write(@path, stored)
            err.puts("[hideout] generated secrets in #{@path}; back this file up with your database")
          end
          missing.each { |name| env[name] = stored.fetch(name) }
        end
        @generated
      end

      # New keys on an install that already has users would make every encrypted
      # column unreadable: put the file back the way it was and stop.
      # has_users is :unknown when the database could not be reached: keys generated
      # then are not kept either, since the next boot might find users after all.
      # has_users false confirms a fresh install, so later boots keep the keys.
      def check_existing_data!(has_users:)
        return if generated.to_a.empty?

        if has_users == false
          with_lock(path) { FileUtils.rm_f(unconfirmed_path) }
          @generated = []
          return
        end

        reject!
        if has_users == :unknown
          raise Unreadable, "[hideout] could not reach the database to confirm a fresh install, so the secrets " \
                            "generated in #{path} were not kept. Start again once the database is reachable"
        end
        raise Unreadable, "[hideout] generated new secrets in #{path}, but the database already has users. " \
                          "Restore the old hideout-secrets.yml (or set SECRET_KEY_BASE and the " \
                          "ACTIVE_RECORD_ENCRYPTION_* variables) and start again"
      end

      def reject!
        with_lock(path) do
          if @previous
            write(path, @previous)
          elsif File.exist?(path)
            File.rename(path, "#{path}.rejected")
          end
          FileUtils.rm_f(unconfirmed_path)
        end
        @generated = []
      end

      private

      def blank?(value) = value.to_s.strip.empty?

      def with_lock(path, &)
        FileUtils.mkdir_p(File.dirname(path))
        File.open("#{path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          yield
        end
      rescue SystemCallError => e
        raise Unreadable, "[hideout] cannot write secrets file #{path}: #{e.message}"
      end

      def unconfirmed_path = "#{path}.unconfirmed"

      # { "generated" => [names], "previous" => the file's content before them, or nil }
      def read_unconfirmed
        return unless File.exist?(unconfirmed_path)

        data = YAML.safe_load(File.read(unconfirmed_path))
        previous = data["previous"] if data.is_a?(Hash)
        unless data.is_a?(Hash) && data["generated"].is_a?(Array) && data["generated"].all?(String) &&
               (previous.nil? || (previous.is_a?(Hash) && previous.all? { |key, value| key.is_a?(String) && value.is_a?(String) }))
          raise Unreadable, "[hideout] cannot read #{unconfirmed_path}: expected generated names and the previous secrets"
        end

        data
      rescue Psych::Exception, SystemCallError => e
        raise Unreadable, "[hideout] cannot read #{unconfirmed_path}: #{e.message}"
      end

      def path_for(env, root)
        value = env["HIDEOUT_SECRETS_FILE"].to_s.strip
        File.expand_path(value.empty? ? DEFAULT_FILE : value, root)
      end

      def read(path)
        return {} unless File.exist?(path)

        data = YAML.safe_load(File.read(path)) || {}
        unless data.is_a?(Hash) && data.all? { |key, value| key.is_a?(String) && value.is_a?(String) }
          raise Unreadable, "[hideout] cannot read secrets file #{path}: expected a mapping of names to strings"
        end

        data
      rescue Psych::Exception, SystemCallError => e
        raise Unreadable, "[hideout] cannot read secrets file #{path}: #{e.message}"
      end

      def write(path, values)
        tmp = "#{path}.#{Process.pid}.tmp"
        FileUtils.mkdir_p(File.dirname(path))
        File.open(tmp, File::WRONLY | File::CREAT | File::TRUNC, 0o600) { |file| file.write(YAML.dump(values)) }
        File.chmod(0o600, tmp)
        File.rename(tmp, path)
      rescue SystemCallError => e
        FileUtils.rm_f(tmp)
        raise Unreadable, "[hideout] cannot write secrets file #{path}: #{e.message}"
      end

      def generate(name)
        name == "SECRET_KEY_BASE" ? SecureRandom.hex(64) : SecureRandom.alphanumeric(32)
      end
    end
  end
end
