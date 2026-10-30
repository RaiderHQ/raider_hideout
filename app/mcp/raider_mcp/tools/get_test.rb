module RaiderMcp
  module Tools
    class GetTest < Base
      tool_name "get_test"
      description "One test: its statistics on the default branch over the last 7 days, its last 20 results on any branch, " \
                  "its flakiness verdict per branch, and its quarantine with the last 20 changes."
      input_schema(
        properties: { project: PROJECT, test_id: { type: "integer", description: "A test id, from search_tests or a build's failures" } },
        required: %w[project test_id]
      )
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.test_case(arguments[:project], arguments[:test_id])

        def summary(test, _arguments)
          location = [ test[:file_path], test[:line_number] ].compact.join(":")
          text = +"#{test[:full_name]} (#{location}): last #{test[:last_status] || 'not run'}"
          text << ", pass rate #{test[:pass_rate]}%" if test[:pass_rate]
          flaky = test[:verdicts].select { |verdict| verdict[:flaky] }.map { |verdict| verdict[:branch] }
          text << ", flaky on #{flaky.join(', ')}" if flaky.any?
          quarantine = test[:quarantine]
          text << "; quarantined until #{date(quarantine[:expires_at])} (#{quarantine[:reason]})" if quarantine
          text
        end
      end
    end
  end
end
