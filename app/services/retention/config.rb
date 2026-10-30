module Retention
  # How long attachments and test results are kept, from RETENTION_ATTACHMENT_DAYS
  # and RETENTION_RESULT_DAYS, for the whole server.
  Config = Data.define(:attachment_days, :result_days) do
    def self.from(env)
      attachment_days = days(env, "RETENTION_ATTACHMENT_DAYS", 30)
      result_days = days(env, "RETENTION_RESULT_DAYS", 90)
      if attachment_days > result_days
        raise ArgumentError, "RETENTION_ATTACHMENT_DAYS (#{attachment_days}) must not exceed RETENTION_RESULT_DAYS (#{result_days})"
      end

      new(attachment_days: attachment_days, result_days: result_days)
    end

    def self.days(env, name, default)
      raw = env[name].to_s.strip
      return default if raw.empty?

      value = Integer(raw, 10, exception: false)
      raise ArgumentError, "#{name} must be a whole number of days, at least 1 (got #{raw.inspect})" unless value && value >= 1

      value
    end
    private_class_method :days
  end
end
