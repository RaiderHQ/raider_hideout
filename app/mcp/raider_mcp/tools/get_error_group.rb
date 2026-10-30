module RaiderMcp
  module Tools
    class GetErrorGroup < Base
      tool_name "get_error_group"
      description "One error group: its exception, sample message and frame, when it was first and last seen, " \
                  "and up to 50 affected tests, most recently failed first."
      input_schema(
        properties: { project: PROJECT, error_group_id: { type: "integer", description: "An error group id, from list_error_groups" } },
        required: %w[project error_group_id]
      )
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.error_group(arguments[:project], arguments[:error_group_id])

        def summary(group, _arguments)
          "#{group[:exception_class]}: #{first_line(group[:sample_message], 200)} — #{plural(group[:affected_tests], 'test')} " \
            "affected, first seen #{date(group[:first_seen_at])}, last seen #{date(group[:last_seen_at])}"
        end
      end
    end
  end
end
