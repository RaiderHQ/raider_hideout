module RaiderMcp
  # A tool result (spec §6): a summary of at most 2,000 characters, then the presenter JSON as a
  # second text part and as structuredContent. All text stays within 50,000 characters: a list
  # that does not fit is cut, and the summary ends by saying how much is shown. The summary may
  # be a callable taking the cut payload, so it describes only what the JSON carries.
  module Result
    SUMMARY_LIMIT = 2_000
    TEXT_LIMIT = 50_000
    JSON_LIMIT = TEXT_LIMIT - SUMMARY_LIMIT

    module_function

    def ok(summary, payload, list_key: nil)
      payload, note = fit(payload, list_key)
      summary = summary.call(payload) if summary.respond_to?(:call)
      MCP::Tool::Response.new([ text(with_note(summary, note)), text(JSON.generate(payload)) ], structured_content: payload)
    end

    def error(message)
      MCP::Tool::Response.new([ text(message.to_s.truncate(SUMMARY_LIMIT)) ], error: true)
    end

    def text(value)
      { type: "text", text: value }
    end

    def with_note(summary, note)
      return summary.to_s.truncate(SUMMARY_LIMIT) unless note

      "#{summary.to_s.truncate(SUMMARY_LIMIT - note.length - 1)} #{note}"
    end

    # The longest prefix of the list whose JSON fits, found by bisection.
    def fit(payload, list_key)
      return [ payload, nil ] if list_key.nil? || JSON.generate(payload).length <= JSON_LIMIT

      items = payload.fetch(list_key)
      low = 0
      high = items.size
      while low < high
        mid = (low + high + 1) / 2
        if JSON.generate(payload.merge(list_key => items.first(mid))).length <= JSON_LIMIT
          low = mid
        else
          high = mid - 1
        end
      end
      [ payload.merge(list_key => items.first(low)), note(payload, list_key, low, items.size) ]
    end

    def note(payload, list_key, shown, size)
      meta = payload[:meta]
      if meta
        return "showing #{shown} of #{meta[:total]}; page cut to fit, pass a smaller per_page" if shown < size

        return "showing #{shown} of #{meta[:total]}; pass page: #{meta[:page] + 1}"
      end

      "showing #{shown} of #{size} #{list_key}"
    end
  end
end
