module ExploreHelper
  RANGE_LABELS = { "24h" => "Last 24 hours", "7d" => "Last 7 days", "30d" => "Last 30 days", "90d" => "Last 90 days" }.freeze
  SORT_LABELS = { "failures" => "Most failures", "recent" => "Most recent", "duration" => "Slowest", "name" => "Name" }.freeze
  FIELD_CLASSES = "w-full rounded-md border border-neutral-bdr px-3 py-2 text-sm".freeze

  def range_phrase(since) = RANGE_LABELS.fetch(since).delete_prefix("Last ")

  def sort_options(level)
    SORT_LABELS.reject { |key, _| level == "results" && key == "failures" }.map { |key, label| [ label, key ] }
  end

  def explore_path_for(level: @level, filter: @filter, **extra)
    project_explore_path(current_project, level: level, q: filter.to_query, view: @view&.id, **extra)
  end
end
