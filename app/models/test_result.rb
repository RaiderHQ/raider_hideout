class TestResult < ApplicationRecord
  # Results whose failure details are kept and grouped (spec §5.1).
  FAILING_STATUSES = %w[failed quarantined].freeze
  STEPS_LIMIT = 200
  STEP_TITLE_LIMIT = 500
  COMPARISONS_LIMIT = 50
  COMPARISON_STATUSES = %w[passed failed created updated].freeze
  COMPARISON_NAME_LIMIT = 100
  COMPARISON_BASELINE_LIMIT = 300
  COMPARISON_NAME_FORMAT = %r{\A[A-Za-z0-9_/-]+\z}

  belongs_to :run
  belongs_to :test_case
  belongs_to :error_group, optional: true
  has_many_attached :attachments

  scope :visible_to, ->(user) { joins(:run).where(runs: { project_id: user.projects.select(:id) }) }

  # Tags as one lowercased, |-delimited string ("|smoke|login|"), so a tag filter is a
  # portable LIKE on both SQLite and Postgres (spec §4.4).
  def self.tags_text_for(tags)
    names = Array(tags).map { |tag| normalize_tag(tag) }.reject(&:empty?).uniq
    names.empty? ? "" : "|#{names.join('|')}|"
  end

  def self.normalize_tag(tag)
    tag.to_s.downcase.delete("|").strip
  end

  # A recorded test's steps with the failed one's 0-based index, or nil (failed-step spec §3):
  # anything malformed is dropped, never rejected.
  def self.normalized_steps(value)
    return unless value.is_a?(Hash) && value.key?("failed")

    items = value["items"]
    return unless items.is_a?(Array) && items.size.between?(1, STEPS_LIMIT)
    return unless items.all? { |item| item.is_a?(Hash) && item["id"].is_a?(String) && item["id"].present? && item["title"].is_a?(String) }

    failed = value["failed"]
    return unless failed.nil? || (failed.is_a?(Integer) && failed.between?(0, items.size - 1))

    { "items" => items.map { |item| { "id" => item["id"], "title" => item["title"].first(STEP_TITLE_LIMIT) } }, "failed" => failed }
  end

  # A failed test's screenshot comparisons (screenshot-comparison spec): only well-formed entries
  # survive, field by field, so what is stored is always safe to render. Never raises.
  def self.normalized_comparisons(value)
    return unless value.is_a?(Array)

    entries = value.filter_map { |entry| normalized_comparison(entry) }
    return if entries.empty?

    failed, rest = entries.partition { |entry| entry["status"] == "failed" }
    (failed + rest).first(COMPARISONS_LIMIT)
  end

  def self.normalized_comparison(entry)
    return unless entry.is_a?(Hash)

    name = entry["name"]
    return unless name.is_a?(String) && name.length <= COMPARISON_NAME_LIMIT && name.match?(COMPARISON_NAME_FORMAT)
    return unless COMPARISON_STATUSES.include?(entry["status"])

    baseline = entry["baseline"]
    {
      "name" => name, "status" => entry["status"],
      "baseline" => (baseline if baseline.is_a?(String) && baseline.length <= COMPARISON_BASELINE_LIMIT),
      "diff_pixels" => comparison_count(entry["diff_pixels"]), "diff_ratio" => comparison_number(entry["diff_ratio"]),
      "threshold" => comparison_number(entry["threshold"]), "max_diff_pixels" => comparison_count(entry["max_diff_pixels"]),
      "max_diff_ratio" => comparison_number(entry["max_diff_ratio"]),
      "expected_size" => comparison_size(entry["expected_size"]), "actual_size" => comparison_size(entry["actual_size"])
    }
  end

  def self.comparison_count(value)
    value if value.is_a?(Integer) && value >= 0
  end

  def self.comparison_number(value)
    value if (value.is_a?(Integer) || (value.is_a?(Float) && value.finite?)) && value >= 0
  end

  def self.comparison_size(value)
    value.dup if value.is_a?(Array) && value.size == 2 && value.all? { |side| comparison_count(side) }
  end

  private_class_method :normalized_comparison, :comparison_count, :comparison_number, :comparison_size

  # Failed first, then quarantined, then the rest: files by their most urgent result, then path;
  # within a file by rank, then name, then run.
  def self.grouped_for_display(results)
    results.group_by { |r| r.test_case.file_path }
           .sort_by { |file, rs| [ rs.map { |r| display_rank(r) }.min, file ] }
           .map { |file, rs| [ file, rs.sort_by { |r| [ display_rank(r), r.test_case.full_name, r.run_id.to_i, r.id.to_i ] } ] }
  end

  def self.display_rank(result)
    FAILING_STATUSES.index(result.status) || FAILING_STATUSES.size
  end

  def attachment_name(attachment)
    attachment.blob.metadata["name"].presence || attachment.filename.to_s
  end
end
