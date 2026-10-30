# Renders a build as the Markdown body of a pull request comment.
class BuildSummary
  MARKER = "<!-- raider-reporter:build-comment -->".freeze
  MAX_FAILURES = 10
  MAX_FLAKY = 5
  MAX_TOP_ERRORS = 3
  MAX_ERROR_LENGTH = 120
  MAX_CELL_LENGTH = 200
  RANK = { new_failure: 0, still_failing: 1 }.freeze
  ESCAPED = /[\\|*_`\[\]<>&~]/
  GATE_ICONS = { "passed" => "✅", "failed" => "❌", "pending" => "⏳" }.freeze

  def initialize(build, url:)
    @build = build
    @url = url
  end

  def state
    @build.status
  end

  def markdown
    sections = [ MARKER, headline, gate_line, top_errors_section, failures_section, fixed_line, flaky_section, waiting_line, "[View build](#{@url})" ]
    "#{sections.compact.join("\n\n")}\n"
  end

  private

  def headline
    parts = []
    parts << "#{@build.failed_count} failed" if @build.failed_count.positive?
    parts << "#{@build.quarantined_count} quarantined" if @build.quarantined_count.positive?
    parts << "#{@build.passed_count} passed"
    parts << "#{@build.skipped_count} skipped" if @build.skipped_count.positive?
    parts << "#{@build.pending_count} pending" if @build.pending_count.positive?
    text = "**Raider: #{state}** - #{parts.join(', ')}"
    text += " (#{@build.shard_progress} shards)" if @build.shard_progress
    text += " (#{@build.duration_label})" if @build.duration_ms
    text += comparison_suffix if comparison
    text
  end

  # Only for a passed/failed verdict, or a pending one when the project has an enabled
  # rule; "none" never shows (spec §4.5).
  def gate_line
    report = @build.gate_report
    state = report.state
    return unless report.evaluated? || (state == "pending" && @build.project.gate_enabled?)

    text = "**Gate:** #{GATE_ICONS.fetch(state)} #{state}"
    failed = report.failed_rules.map { |rule| md_escape(rule.rule == "pass_rate" ? "pass rate #{rule.detail}" : rule.detail) }
    failed.empty? ? text : "#{text} — #{failed.join('; ')}"
  end

  # Groups with at least two failures in this build, most failures first. Two
  # queries regardless of how many groups there are.
  def top_errors_section
    return if top_error_counts.empty?

    groups = ErrorGroup.where(id: top_error_counts.map(&:first)).index_by(&:id)
    lines = top_error_counts.map { |id, count| top_error_line(groups.fetch(id), count) }
    [ "### Top errors", "", *lines ].join("\n")
  end

  def top_error_counts
    @top_error_counts ||= failing_scope.where.not(error_group_id: nil).group(:error_group_id)
                                      .having("COUNT(*) >= 2").order(Arel.sql("COUNT(*) DESC"), :error_group_id)
                                      .limit(MAX_TOP_ERRORS).pluck(:error_group_id, Arel.sql("COUNT(*)"))
  end

  def top_error_line(group, count)
    frame = group.frame.presence
    where = frame ? " in `#{code_span(frame)}`" : ""
    message = group.normalized_message.presence
    detail = message ? " — #{md_escape(message)}" : ""
    "- **#{count} tests** · `#{code_span(group.exception_class)}`#{where}#{detail} ([details](#{error_group_url(group)}))"
  end

  def error_group_url(group)
    uri = URI.parse(@url)
    path = Rails.application.routes.url_helpers.project_error_path(@build.project, group)
    "#{uri.scheme}://#{uri.authority}#{path}"
  end

  # Backticks would end the code span early; swap them for apostrophes.
  def code_span(value)
    value.to_s.gsub(/\p{Cf}/, "").gsub(/[[:cntrl:]]/, " ").tr("`", "'")
  end

  def failures_section
    return if failed_total.zero?

    header = comparison ? "| File | Test | Error | Status |" : "| File | Test | Error |"
    rows = failed_results.map { |result| failure_row(result) }
    lines = [ "### Failed tests", "", header, comparison ? "| --- | --- | --- | --- |" : "| --- | --- | --- |", *rows ]
    lines << "" << more_text(failed_total - MAX_FAILURES) if failed_total > MAX_FAILURES
    lines.join("\n")
  end

  def failure_row(result)
    cells = [ clip(result.test_case.file_path), clip(result.test_case.full_name) ].map { |v| md_escape(v) }
    cells << md_escape(first_line(result.failure_message))
    cells << md_escape(status_label(result.test_case_id)) if comparison
    "| #{cells.join(' | ')} |"
  end

  def status_label(test_case_id)
    Builds::FailureTag.for(test_case_id, comparison, verdicts, @build.comparison_branch)&.first.to_s
  end

  def comparison
    return @comparison if defined?(@comparison)

    candidate = Builds::Comparison.new(@build) if @build.baseline_assigned_at
    @comparison = candidate&.available? && !candidate.expired? ? candidate : nil
  end

  def verdicts
    @verdicts ||= TestCaseVerdict.for_cases(failed_scope.select(:test_case_id),
                                            branch: @build.branch, default_branch: @build.comparison_branch)
  end

  def comparison_suffix
    count = comparison.counts[:new_failures]
    branch = md_escape(comparison.branch)
    count.zero? ? " · no new failures vs #{branch}" : " · #{count} new #{'failure'.pluralize(count)} vs #{branch}"
  end

  def fixed_line
    return unless comparison

    fixed = comparison.counts[:fixed]
    "Fixed vs #{md_escape(comparison.branch)}: #{fixed}" if fixed.positive?
  end

  def flaky_section
    return if flaky_total.zero?

    items = flaky_cases.map { |tc| "- #{md_escape(clip(tc.full_name))} (#{md_escape(clip(tc.file_path))})" }
    lines = [ "### Flaky tests", "", *items ]
    lines << "" << more_text(flaky_total - MAX_FLAKY) if flaky_total > MAX_FLAKY
    lines.join("\n")
  end

  def waiting_line
    return unless state == "incomplete" && @build.expected_shards

    missing = [ @build.expected_shards - @build.runs.size, 1 ].max
    "Waiting for #{missing} more #{'shard'.pluralize(missing)}"
  end

  def more_text(count)
    "…and #{count} more — see the build"
  end

  def failed_scope
    TestResult.where(run_id: @build.runs.select(:id), status: "failed")
  end

  def failing_scope
    TestResult.where(run_id: @build.runs.select(:id), status: TestResult::FAILING_STATUSES)
  end

  def failed_total
    @failed_total ||= failed_scope.count
  end

  def failed_results
    @failed_results ||= comparison ? ranked_failed_results : failed_scope.includes(:test_case).order(:id).limit(MAX_FAILURES).to_a
  end

  # New failures first, then still failing, then the rest; file then test name within each group.
  def ranked_failed_results
    rows = failed_scope.includes(:test_case).order(:id).to_a
    rows.sort_by! do |r|
      [ RANK.fetch(comparison.status_for(r.test_case_id), 2), r.test_case.file_path.to_s, r.test_case.full_name.to_s, r.id ]
    end
    rows.first(MAX_FAILURES)
  end

  def flaky_ids
    @flaky_ids ||= @build.flaky_test_case_ids
  end

  def flaky_total
    flaky_ids.size
  end

  def flaky_cases
    @flaky_cases ||= TestCase.where(id: flaky_ids).order(:file_path, :full_name).limit(MAX_FLAKY).to_a
  end

  def clip(value)
    text = value.to_s
    text.length > MAX_CELL_LENGTH ? "#{text[0, MAX_CELL_LENGTH]}…" : text
  end

  def first_line(message)
    line = message.to_s.strip.lines.first.to_s.strip
    line.length > MAX_ERROR_LENGTH ? line[0, MAX_ERROR_LENGTH] : line
  end

  # Every interpolated value goes through here: no raw HTML, no table breakage.
  def md_escape(value)
    value.to_s.gsub(/\p{Cf}/, "").gsub(/[\r\n]+/, " ").gsub(/[[:cntrl:]]/, "")
         .gsub(ESCAPED) { |c| "\\#{c}" }
         .gsub(/([@#])(?=\w)/, "\\1\u200B")
  end
end
