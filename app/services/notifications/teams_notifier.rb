module Notifications
  class TeamsNotifier
    SCHEMA = "http://adaptivecards.io/schemas/adaptive-card.json".freeze

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
      {
        type: "message",
        attachments: [ {
          contentType: "application/vnd.microsoft.card.adaptive",
          contentUrl: nil,
          content: { "$schema": SCHEMA, type: "AdaptiveCard", version: "1.4",
                     body: body(message), actions: actions(message) }
        } ]
      }
    end

    private

    # User-controlled strings only ever appear in TextRun.text, which Teams does not parse as markdown.
    def body(message)
      list = [
        rich([ run(message.title, weight: "Bolder", size: "Medium") ]),
        rich([ run(message.summary) ])
      ]
      list << rich([ run("Branch: #{message.branch}") ]) if message.branch.present?
      list << rich([ run("Commit: #{message.commit}") ]) if message.commit.present?
      list << { type: "FactSet", facts: [ { title: "Pass rate", value: "#{message.pass_rate}%" } ] } if message.pass_rate
      list.concat(section("Failures", message.failures))
      list.concat(section("New flaky tests", message.new_flaky))
      list
    end

    def section(heading, items)
      return [] if items.empty?

      [ rich([ run(heading, weight: "Bolder") ]), *items.map { |item| rich([ run(item) ], spacing: "None") } ]
    end

    def rich(inlines, spacing: nil)
      block = { type: "RichTextBlock", inlines: inlines }
      block[:spacing] = spacing if spacing
      block
    end

    def run(text, **options)
      { type: "TextRun", text: text.to_s, **options }
    end

    def actions(message)
      [ [ "View build", message.build_url ], [ "Pull request", message.pr_url ] ]
        .select { |_, url| SafeUrl.valid?(url) }.map { |title, url| { type: "Action.OpenUrl", title: title, url: url } }
    end
  end
end
