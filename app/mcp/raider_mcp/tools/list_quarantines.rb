module RaiderMcp
  module Tools
    class ListQuarantines < Base
      tool_name "list_quarantines"
      description "A project's active quarantines (up to 100), soonest expiry first, with the reason and who quarantined each test."
      input_schema(properties: { project: PROJECT }, required: [ "project" ])
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.quarantines(arguments[:project], per_page: Base::LIST_LIMIT)

        def list_key = :data

        def summary(payload, arguments)
          head = "#{plural(payload[:meta][:total], 'quarantined test')} in #{arguments[:project]}"
          return "#{head}." if payload[:data].empty?

          tests = payload[:data].map { |entry| "#{entry[:full_name]} until #{date(entry[:expires_at])} (#{entry[:reason]})" }
          "#{head}: #{tests.join('; ')}"
        end
      end
    end
  end
end
