module RaiderMcp
  module Tools
    class ListErrorGroups < Base
      tool_name "list_error_groups"
      description "A project's error groups (failures with the same exception, message and frame), last seen first, " \
                  "50 a page, with the number of tests each affected. since: 24h, 7d, 30d (default) or 90d."
      input_schema(
        properties: { project: PROJECT, since: { type: "string", enum: Search::Filter::RANGES.keys }, page: PAGE, per_page: PER_PAGE },
        required: [ "project" ]
      )
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.error_groups(arguments[:project], arguments.slice(:since, :page, :per_page))

        def list_key = :data

        def summary(payload, arguments)
          head = "#{plural(payload[:meta][:total], 'error group')} in #{arguments[:project]}"
          return "#{head}." if payload[:data].empty?

          groups = payload[:data].map do |group|
            "#{group[:exception_class]} in #{plural(group[:affected_tests], 'test')}: #{first_line(group[:sample_message])}"
          end
          "#{head}: #{groups.join('; ')}"
        end
      end
    end
  end
end
