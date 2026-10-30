module AnalyticsHelper
  # The project page's chart markup (240 px, loading text), without inline styles.
  CHART_HTML = %(<div id="%{id}" class="h-[240px] w-full text-center leading-[240px] text-sm text-neutral-mid">%{loading}</div>).freeze
  NOTHING = "Nothing to show for this filter.".freeze
  BUILD_NOTE = "Build numbers ignore file: and tag:".freeze

  def analytics_no_builds_text(filter = @filter) = "No builds on #{filter.branch} in the last #{filter.days} days."

  # The empty-state text for a list or chart, or nil when it has something to show. "No builds on
  # <branch>..." only when the window has no builds and no executed results matching the filter;
  # otherwise "Nothing to show for this filter."
  def analytics_empty_text(rows)
    return if rows.any?

    @no_activity ? analytics_no_builds_text : NOTHING
  end

  def analytics_chart_empty_text(*series)
    analytics_empty_text(series.flat_map { |data| data.filter_map(&:last) })
  end

  def analytics_path_for(query) = project_analytics_path(current_project, q: query.presence)

  def analytics_csv_path(list) = project_analytics_path(current_project, format: :csv, list: list, q: @filter.to_query.presence)

  def analytics_explore_path(**options) = project_explore_path(current_project, q: @filter.explore_query(**options))

  def analytics_test_path(test_case) = project_test_case_path(current_project, test_case, branch: @filter.branch)

  def analytics_duration(ms)
    return "–" if ms.nil?
    return "#{ms} ms" if ms < 1_000
    return "#{(ms / 1_000.0).round(1)}s" if ms < 60_000

    seconds = ms / 1_000
    "#{seconds / 60}m #{seconds % 60}s"
  end

  def analytics_rate(rate) = rate.nil? ? "–" : "#{rate}%"

  # [label, Headline::Number, displayed value] for the four headline tiles.
  def analytics_headline_tiles(headline)
    [
      [ "Builds", headline.builds, headline.builds.value.to_s ],
      [ "Pass rate", headline.pass_rate, analytics_rate(headline.pass_rate.value) ],
      [ "Average build duration", headline.avg_duration_ms, analytics_duration(headline.avg_duration_ms.value) ],
      [ "Flaky tests", headline.flaky, headline.flaky.value.nil? ? "–" : headline.flaky.value.to_s ]
    ]
  end

  def trend_series(points, attribute) = points.map { |point| [ point.date.iso8601, point.public_send(attribute) ] }
end
