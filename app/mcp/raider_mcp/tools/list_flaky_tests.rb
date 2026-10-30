module RaiderMcp
  module Tools
    class ListFlakyTests < Base
      tool_name "list_flaky_tests"
      description "Flaky tests on a branch (default: the default branch), highest flip rate first, 50 a page, " \
                  "with the reason and the build they turned flaky in."
      input_schema(
        properties: { project: PROJECT, branch: { type: "string", description: "Default: the project's default branch" }, page: PAGE, per_page: PER_PAGE },
        required: [ "project" ]
      )
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.flaky_tests(arguments[:project], arguments.slice(:branch, :page, :per_page))

        def list_key = :data

        def summary(payload, arguments)
          head = "#{plural(payload[:meta][:total], 'flaky test')} on #{arguments[:branch].presence || 'the default branch'}"
          return "#{head}." if payload[:data].empty?

          tests = payload[:data].map { |test| "#{test[:full_name]} (flip rate #{((test[:flip_rate] || 0) * 100).round}%)" }
          "#{head}: #{tests.join('; ')}"
        end
      end
    end
  end
end
