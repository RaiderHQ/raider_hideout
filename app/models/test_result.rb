class TestResult < ApplicationRecord
  # Results whose failure details are kept and grouped (spec §5.1).
  FAILING_STATUSES = %w[failed quarantined].freeze

  belongs_to :run
  belongs_to :test_case
  belongs_to :error_group, optional: true
  has_many_attached :attachments

  # Tags as one lowercased, |-delimited string ("|smoke|login|"), so a tag filter is a
  # portable LIKE on both SQLite and Postgres (spec §4.4).
  def self.tags_text_for(tags)
    names = Array(tags).map { |tag| normalize_tag(tag) }.reject(&:empty?).uniq
    names.empty? ? "" : "|#{names.join('|')}|"
  end

  def self.normalize_tag(tag)
    tag.to_s.downcase.delete("|").strip
  end

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
