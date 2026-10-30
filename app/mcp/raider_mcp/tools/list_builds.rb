module RaiderMcp
  module Tools
    class ListBuilds < Base
      tool_name "list_builds"
      description "A project's builds, newest first, 50 a page, with counts, pass rate, gate status and pull request. " \
                  "Filter by branch, status (passed, failed, incomplete) and since (24h, 7d, 30d, 90d)."
      input_schema(
        properties: {
          project: PROJECT,
          branch: { type: "string", description: "Only builds on this branch" },
          status: { type: "string", enum: Api::V1::Public::Reader::BUILD_STATUSES },
          since: { type: "string", enum: Search::Filter::RANGES.keys, description: "Only builds created in this window" },
          page: PAGE,
          per_page: PER_PAGE
        },
        required: [ "project" ]
      )
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.builds(arguments[:project], arguments.slice(:branch, :status, :since, :page, :per_page))

        def list_key = :data

        def summary(payload, arguments)
          head = "#{plural(payload[:meta][:total], 'build')} in #{arguments[:project]}"
          return "#{head}." if payload[:data].empty?

          builds = payload[:data].map { |build| "##{build[:id]} #{build[:branch] || 'no branch'} #{build[:status]}#{percent(build[:pass_rate])}" }
          "#{head}: #{builds.join('; ')}"
        end
      end
    end
  end
end
