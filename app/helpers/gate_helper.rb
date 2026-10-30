# The quality gate on the build page and the builds list (spec §4.5).
module GateHelper
  BADGES = { "passed" => [ "Gate passed", :pass ], "failed" => [ "Gate failed", :fail ], "pending" => [ "Gate pending", :idle ] }.freeze
  LIST_MARKS = { "passed" => "✓", "failed" => "✗", "pending" => "·" }.freeze
  LIST_CLASSES = { "passed" => "text-status-ok", "failed" => "text-status-err", "pending" => "text-neutral-mid" }.freeze
  OUTCOME_ICONS = { "passed" => "✓", "failed" => "✗", "skipped" => "–" }.freeze
  OUTCOME_CLASSES = { "passed" => "text-status-ok", "failed" => "text-status-err", "skipped" => "text-neutral-mid" }.freeze

  # Pending shows only when the project has an enabled rule; none never shows.
  def gate_badge(build, rule_enabled:)
    state = build.gate_report.state
    return if state == "none" || (state == "pending" && !rule_enabled)

    label, kind = BADGES.fetch(state)
    tag.span(label, class: "#{UiHelper::PILL_BASE} #{UiHelper::PILL_STYLES.fetch(kind)}", data: { testid: "gate-badge" })
  end

  # One character per build; no per-row rule lookup, so a null verdict is always "·".
  def gate_list_mark(build)
    state = build.gate_report.state
    tag.span(LIST_MARKS[state].to_s, class: "w-4 flex-shrink-0 text-center text-sm #{LIST_CLASSES[state]}",
                                     title: (state == "none" ? nil : "Gate #{state}"), data: { testid: "gate-cell" })
  end

  # Nil when the rule's section is not on the page (no comparison section → no #comparison link).
  def gate_rule_source(build, rule, comparison:)
    case rule.rule
    when "pass_rate" then "#results"
    when "new_failures" then ("#comparison" if comparison)
    else project_flaky_tests_path(build.project, branch: build.branch)
    end
  end

  def gate_threshold(rule)
    rule.rule == "pass_rate" ? "≥ #{rule.stored['min']}%" : "0"
  end

  def gate_actual(rule)
    return "–" if rule.outcome == "skipped"

    rule.rule == "pass_rate" ? "#{rule.stored['actual']}%" : rule.stored["count"].to_s
  end

  def gate_outcome(rule)
    safe_join([ tag.span(OUTCOME_ICONS.fetch(rule.outcome.to_s, "?"), class: OUTCOME_CLASSES[rule.outcome.to_s]), " ", rule.detail ])
  end
end
