module Builds
  # Computes a build's quality gate verdict once, when the build is ready (spec §4.3),
  # and freezes it with the rule values used. Never raises: an error is logged and
  # leaves the verdict null, so `raider-reporter gate` keeps waiting and then exits 2.
  class Gate
    def self.evaluate!(build)
      new(build).evaluate!
    end

    def initialize(build)
      @build = build
    end

    # True when this call wrote the verdict; false when it was already written or failed.
    def evaluate!
      return false if @build.gate_evaluated_at

      written = write_verdict
      broadcast if written
      written
    end

    private

    # Computes the verdict and claims the row. Only this part reports evaluation failure.
    def write_verdict
      status, result = verdict
      now = Time.current
      # Atomic claim: of two concurrent ready hooks, only one flips the null row.
      Build.where(id: @build.id, gate_evaluated_at: nil)
           .update_all(gate_status: status, gate_result: JSON.generate(result), gate_evaluated_at: now, updated_at: now) == 1
    rescue StandardError => e
      Rails.logger.error("[gate] build #{@build.id}: evaluation failed: #{e.class}: #{e.message}")
      false
    end

    # update_all skips the model's card broadcast; the builds list shows the gate.
    # The verdict is already written, so a failure here is logged apart and never reported as failed evaluation.
    def broadcast
      @build.reload
      @build.broadcast_replace_later_to [ @build.project, :builds ], partial: "builds/build", locals: { build: @build }
    rescue StandardError => e
      Rails.logger.error("[gate] build #{@build.id}: gate verdict broadcast failed: #{e.class}: #{e.message}")
    end

    def verdict
      rule = GateRule.find_by(project_id: @build.project_id)
      return [ "none", { "rules" => {} } ] unless rule&.enabled?

      rules = {}
      rules["pass_rate"] = pass_rate(rule.min_pass_rate) if rule.min_pass_rate.present?
      rules["new_failures"] = new_failures if rule.no_new_failures
      rules["new_flaky"] = new_flaky if rule.no_new_flaky
      status = rules.values.any? { |values| values["outcome"] == "failed" } ? "failed" : "passed"
      evaluated = { "min_pass_rate" => rule.min_pass_rate, "no_new_failures" => rule.no_new_failures,
                    "no_new_flaky" => rule.no_new_flaky }
      [ status, { "rules" => rules, "evaluated_rules" => evaluated } ]
    end

    # Quarantined results never count (D3). Integer division floors exactly like
    # (passed * 100.0 / executed).floor: 97.9% is 97 and never passes 98.
    def pass_rate(min)
      executed = @build.passed_count + @build.failed_count
      return { "min" => min }.merge(skipped("no passed or failed results")) if executed.zero?

      actual = @build.passed_count * 100 / executed
      { "min" => min, "actual" => actual, "outcome" => outcome(actual < min) }
    end

    def new_failures
      comparison = Comparison.new(@build)
      unless @build.baseline_assigned_at && comparison.available?
        return skipped("no baseline build on #{@build.comparison_branch.presence || 'the default branch'}")
      end
      return skipped("baseline results purged") if comparison.expired?

      count = comparison.counts[:new_failures]
      { "count" => count, "baseline_build_id" => comparison.baseline.id, "branch" => comparison.branch,
        "outcome" => outcome(count.positive?) }
    end

    def new_flaky
      return skipped("no branch") if @build.branch.blank?

      count = Notifications::Rules.new_flaky_scope(@build).count
      { "count" => count, "outcome" => outcome(count.positive?) }
    end

    def outcome(failed) = failed ? "failed" : "passed"

    def skipped(reason) = { "outcome" => "skipped", "reason" => reason }
  end
end
