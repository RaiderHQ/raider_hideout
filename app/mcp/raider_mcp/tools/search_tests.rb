module RaiderMcp
  module Tools
    class SearchTests < Base
      tool_name "search_tests"
      description "Search a project's tests with Explore query syntax, one row per test (50 a page). Words match the test " \
                  "name or file. Filters: name:<text>, file:<text>, error:<text> (failure message or class), " \
                  "status:passed|failed|skipped|pending|quarantined (comma-separated, the latest result), " \
                  "branch:<name> (default: the default branch), tag:<tag>, is:flaky, is:quarantined, " \
                  "since:24h|7d|30d|90d (default 7d), sort:failures|recent|duration|name. Quote values with spaces: " \
                  "name:\"user signs in\". Examples: \"status:failed since:30d\", \"is:flaky branch:main\", " \
                  "\"error:Timeout file:spec/checkout\". Unknown filters are ignored and listed in meta.notices."
      input_schema(
        properties: { project: PROJECT, query: { type: "string", description: "An Explore query; empty lists every test" }, page: PAGE, per_page: PER_PAGE },
        required: [ "project" ]
      )
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.test_cases(arguments[:project], { q: arguments[:query], page: arguments[:page], per_page: arguments[:per_page] }.compact)

        def list_key = :data

        def summary(payload, _arguments)
          meta = payload[:meta]
          total = meta[:total]
          text = +plural(total, "test")
          text << %( #{total == 1 ? 'matches' : 'match'} "#{meta[:query]}") if meta[:query].present?
          tests = payload[:data].map do |test|
            "#{test[:full_name]} (#{test[:last_status] || 'not run'}, #{plural(test[:failures], 'failure')})"
          end
          # Notices come before the list: the 2,000-character cut falls on the list's tail.
          text << ". Notices: #{meta[:notices].join(' ')}" if meta[:notices].any?
          text << (meta[:notices].any? ? ". Tests: " : ": ") << tests.join("; ") if tests.any?
          text
        end
      end
    end
  end
end
