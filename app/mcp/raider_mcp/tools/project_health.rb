module RaiderMcp
  module Tools
    class ProjectHealth < Base
      tool_name "project_health"
      description "A project's health on its default branch over the last 30 days: build count and average pass rate, " \
                  "flaky and quarantined tests, the top 5 error groups and the last 10 builds."
      input_schema(properties: { project: PROJECT }, required: [ "project" ])
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.project(arguments[:project])

        def summary(project, _arguments)
          health = project[:health]
          text = +"#{project[:slug]} on #{project[:default_branch]}, last 30 days: #{plural(health[:builds], 'build')}"
          text << ", pass rate #{health[:pass_rate]}%" if health[:pass_rate]
          text << ", #{health[:flaky_count]} flaky, #{health[:quarantined_count]} quarantined"
          if (top = health[:top_error_groups].first)
            text << "; top error: #{top[:exception_class]} (#{plural(top[:affected_tests], 'test')})"
          end
          text
        end
      end
    end
  end
end
