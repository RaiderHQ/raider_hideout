module Notifications
  class SlackNotifier
    MAX_TEXT = 3000
    MAX_HEADER = 150

    def initialize(channel)
      @channel = channel
    end

    def deliver(message)
      HttpPost.call(@channel.webhook_url, payload(message))
      nil
    rescue RetryableError, PermanentError => e
      raise HttpPost.sanitized(e, @channel)
    end

    def payload(message)
      { text: "#{esc(message.title)} — #{esc(message.summary)}", blocks: blocks(message) }
    end

    private

    def blocks(message)
      list = [
        { type: "header", text: { type: "plain_text", text: message.title.truncate(MAX_HEADER) } },
        section(details(message))
      ]
      list << section("*Failures*\n#{bullets(message.failures)}") if message.failures.any?
      list << section("*New flaky tests*\n#{bullets(message.new_flaky)}") if message.new_flaky.any?
      list << { type: "actions", elements: buttons(message) }
      list
    end

    def details(message)
      lines = [ esc(message.summary) ]
      lines << "*Branch:* #{esc(message.branch)}" if message.branch.present?
      lines << "*Commit:* #{esc(message.commit)}" if message.commit.present?
      lines.join("\n")
    end

    def buttons(message)
      [ [ "View build", message.build_url ], [ "Pull request", message.pr_url ] ]
        .select { |_, url| SafeUrl.valid?(url) }.map { |label, url| button(label, url) }
    end

    def button(label, url)
      { type: "button", text: { type: "plain_text", text: label }, url: url }
    end

    def section(text)
      { type: "section", text: { type: "mrkdwn", text: text.truncate(MAX_TEXT) } }
    end

    def bullets(items)
      items.map { |item| "• #{esc(item)}" }.join("\n")
    end

    def esc(value)
      value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end
  end
end
