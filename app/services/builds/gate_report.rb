module Builds
  # Reads a build's frozen gate verdict (spec §4.2) for the API, the PR summary and the
  # build page. The stored JSON is parsed in Ruby; a malformed value reads as no rules.
  class GateReport
    RULES = %w[pass_rate new_failures new_flaky].freeze
    LABELS = { "pass_rate" => "Minimum pass rate", "new_failures" => "No new failures",
               "new_flaky" => "No new flaky tests" }.freeze
    Rule = Data.define(:rule, :outcome, :detail, :stored)

    def self.detail(name, stored)
      return stored["reason"].to_s if stored["outcome"] == "skipped"

      case name
      when "pass_rate"
        "#{stored['actual']}% #{stored['outcome'] == 'failed' ? '<' : '≥'} #{stored['min']}%"
      when "new_failures"
        count = stored["count"].to_i
        "#{count} new #{'failure'.pluralize(count)} vs #{stored['branch']}"
      when "new_flaky"
        count = stored["count"].to_i
        "#{count} new flaky #{'test'.pluralize(count)}"
      end
    end

    def initialize(build)
      @build = build
    end

    def state
      @build.gate_status || "pending"
    end

    def evaluated?
      %w[passed failed].include?(state)
    end

    def rules
      return [] unless evaluated?

      @rules ||= RULES.filter_map do |name|
        stored = stored_rules[name]
        Rule.new(rule: name, outcome: stored["outcome"], detail: self.class.detail(name, stored), stored: stored) if stored.is_a?(Hash)
      end
    end

    def failed_rules
      rules.select { |rule| rule.outcome == "failed" }
    end

    private

    def stored_rules
      @stored_rules ||= parse_stored_rules
    end

    def parse_stored_rules
      data = JSON.parse(@build.gate_result.to_s)
      data.is_a?(Hash) && data["rules"].is_a?(Hash) ? data["rules"] : {}
    rescue JSON::ParserError
      {}
    end
  end
end
