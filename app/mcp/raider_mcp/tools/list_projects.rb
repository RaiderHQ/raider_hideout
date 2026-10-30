module RaiderMcp
  module Tools
    class ListProjects < Base
      tool_name "list_projects"
      description "List the Raider projects you can see (up to 100), newest build first, each with its latest build. " \
                  "Pass a project's slug to the other tools."
      input_schema(properties: {})
      annotations(READ_ONLY)

      class << self
        def read(reader, _arguments) = reader.projects(per_page: Base::LIST_LIMIT)

        def list_key = :data

        def summary(payload, _arguments)
          projects = payload[:data]
          return "No projects yet. Create one in Raider, or ask to be added to an organization." if projects.empty?

          lines = projects.map do |project|
            build = project[:latest_build]
            latest = if build
              "latest build ##{build[:id]} #{build[:status]}#{percent(build[:pass_rate])} on #{build[:branch] || 'no branch'}"
            else
              "no builds yet"
            end
            "#{project[:slug]} (#{project[:name]}): #{latest}"
          end
          "#{plural(payload[:meta][:total], 'project')}: #{lines.join('; ')}"
        end
      end
    end
  end
end
