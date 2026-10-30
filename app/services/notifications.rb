module Notifications
  class PermanentError < StandardError
    # Raw (unredacted) response body, capped. Never put it in the message before redaction.
    attr_reader :body

    def initialize(message = nil, body: nil)
      super(message)
      @body = body
    end
  end

  class RetryableError < StandardError
    attr_reader :retry_after, :body

    def initialize(message = nil, retry_after: nil, body: nil)
      super(message)
      @retry_after = retry_after
      @body = body
    end
  end

  def self.notifier_for(channel)
    notifier = {
      "slack" => SlackNotifier,
      "teams" => TeamsNotifier,
      "email" => EmailNotifier
    }.fetch(channel.kind)
    notifier.new(channel)
  end
end
