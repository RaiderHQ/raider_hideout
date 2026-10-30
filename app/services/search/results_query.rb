module Search
  # One row per result on the branch in range (spec §4.3).
  class ResultsQuery < BaseQuery
    ORDERS = {
      "recent" => "runs.created_at DESC, test_results.id DESC",
      "duration" => "test_results.duration_ms DESC, test_results.id DESC",
      "name" => "test_cases.full_name ASC, test_results.id DESC"
    }.freeze
    MESSAGE_COLUMNS = %w[test_results.failure_message test_results.exception_class].freeze
    TEXT_COLUMNS = (%w[test_cases.full_name test_cases.file_path] + MESSAGE_COLUMNS).freeze

    def self.first_line(message) = message.to_s.strip.lines.first.to_s.strip.truncate(160)

    def count = scope.count

    def page(limit:, offset:)
      scope.preload(:test_case, run: :build).order(Arel.sql(ORDERS.fetch(@filter.sort_for("results"))))
           .limit(limit).offset(offset).to_a
    end

    private

    def scope
      @scope ||= begin
        s = in_range
        s = @filter.text.reduce(s) { |acc, word| contains(acc, TEXT_COLUMNS, word) }
        s = contains(s, %w[test_cases.full_name], @filter.name) if @filter.name
        s = contains(s, %w[test_cases.file_path], @filter.file) if @filter.file
        s = contains(s, MESSAGE_COLUMNS, @filter.error) if @filter.error
        s = s.where(status: @filter.statuses) if @filter.statuses.any?
        s = s.where(test_case_id: flaky_case_ids) if @filter.flaky
        s = s.where(test_case_id: quarantined_case_ids) if @filter.quarantined
        with_tags(s)
      end
    end
  end
end
