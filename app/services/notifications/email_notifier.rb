require "net/smtp"

module Notifications
  class EmailNotifier
    MAIL_ERRORS = [ Net::SMTPError, Timeout::Error, IOError, SocketError, SystemCallError, OpenSSL::SSL::SSLError ].freeze

    def initialize(channel)
      @channel = channel
    end

    def deliver(message)
      NotificationMailer.build_notification(@channel, message).deliver_now
      nil
    rescue *MAIL_ERRORS => e
      raise RetryableError, @channel.redact("#{e.class}: #{e.message}")
    end
  end
end
