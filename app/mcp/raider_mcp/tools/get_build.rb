module RaiderMcp
  module Tools
    class GetBuild < Base
      tool_name "get_build"
      description "One build in full: counts, the quality gate and its rules, the comparison with its baseline " \
                  "(new and still-failing tests), up to 200 failures with messages and error groups, and its shards. " \
                  "build_id is a build id, or \"latest\" for the newest build on branch (default: the default branch)."
      input_schema(
        properties: {
          project: PROJECT,
          build_id: { type: [ "integer", "string" ], description: "A build id, or \"latest\"" },
          branch: { type: "string", description: "With latest: the branch (default: the project's default branch)" }
        },
        required: %w[project build_id]
      )
      annotations(READ_ONLY)

      class << self
        def read(reader, arguments) = reader.build(arguments[:project], arguments[:build_id], arguments.slice(:branch))

        def list_key = :failures

        def summary(build, _arguments)
          counts = build[:counts]
          text = +"Build ##{build[:id]} on #{build[:branch] || 'no branch'}: #{build[:status]}"
          text << ", #{build[:pass_rate]}% (#{counts[:passed]}/#{counts[:passed] + counts[:failed] + counts[:quarantined]})" if build[:pass_rate]
          new_failures = new_failures_note(build)
          gate = gate_note(build[:gate], skip_new_failures: new_failures.present?)
          text << ", #{gate}" if gate
          text << "; #{new_failures}" if new_failures
          text << "; results purged by retention" if build[:results_purged]
          text
        end

        private

        def gate_note(gate, skip_new_failures:)
          return unless %w[passed failed].include?(gate[:state])

          failed = gate[:rules].select { |rule| rule[:outcome] == "failed" }
          failed = failed.reject { |rule| rule[:rule] == "new_failures" } if skip_new_failures
          details = failed.map { |rule| rule[:rule] == "pass_rate" ? "pass rate #{rule[:detail]}" : rule[:detail] }
          details.any? ? "gate #{gate[:state]} — #{details.join('; ')}" : "gate #{gate[:state]}"
        end

        def new_failures_note(build)
          comparison = build[:comparison]
          count = comparison[:counts]&.fetch(:new_failures, 0).to_i
          return unless comparison[:available] && count.positive?

          names = build[:failures].select { |failure| comparison[:new_failure_test_ids].include?(failure[:test_case_id]) }
                                  .map { |failure| failure[:full_name] }.uniq.first(5)
          note = "#{count} new #{'failure'.pluralize(count)} vs #{comparison[:branch]}"
          names.any? ? "#{note}: #{names.join(', ')}" : note
        end
      end
    end
  end
end
