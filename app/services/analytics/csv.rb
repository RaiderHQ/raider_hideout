module Analytics
  # One list of the Analytics page as CSV (spec 2026-10-28 §4.6): the full ranked list up to
  # LIMIT rows in the page's order and columns, plus test_id and url for tests, or one row per
  # trend bucket. Cells that a spreadsheet would run as a formula are prefixed with '.
  class Csv
    LISTS = %w[failing slowest flaky files trend].freeze
    LIMIT = 5_000
    FORMULA = /\A[=+\-@\t\r]/
    HEADERS = {
      "failing" => %w[test_id test file failures executed failure_rate last_failure flaky quarantined url],
      "slowest" => %w[test_id test file avg_duration_ms max_duration_ms runs total_duration_ms url],
      "flaky" => %w[test_id test file flip_rate reason flaky_since_build samples quarantined url],
      "files" => %w[file tests executed failures failure_rate total_duration_ms],
      "trend" => %w[date executed failed failure_rate avg_test_duration_ms avg_build_duration_ms flaky_count]
    }.freeze

    def self.guard(value)
      text = value.respond_to?(:iso8601) ? value.iso8601 : value&.to_s
      text&.match?(FORMULA) ? "'#{text}" : text
    end

    # `test_url` maps a TestCase to the absolute URL of its test page.
    def initialize(project, filter, list:, test_url:, now: Time.current)
      raise ArgumentError, "unknown list #{list.inspect}" unless LISTS.include?(list)

      @project = project
      @filter = filter
      @list = list
      @test_url = test_url
      @now = now
    end

    def filename = "#{@project.slug}-#{@list}-#{@now.to_date.iso8601}.csv"

    def to_csv
      CSV.generate do |csv|
        csv << HEADERS.fetch(@list)
        rows.each { |row| csv << row.map { |value| self.class.guard(value) } }
      end
    end

    private

    def rows
      case @list
      when "failing", "slowest" then test_rows
      when "flaky" then flaky_rows
      when "files" then file_rows
      when "trend" then trend_rows
      end
    end

    def test_rows
      TestRanking.new(@project, @filter, mode: @list, now: @now).rows(limit: LIMIT).map do |row|
        test = row.test_case
        values = if @list == "failing"
          [ row.failures, row.executed, row.failure_rate, row.last_failure_at&.utc, row.flaky, row.quarantined ]
        else
          [ row.avg_duration_ms, row.max_duration_ms, row.executed, row.total_duration_ms ]
        end
        [ test.id, test.full_name, test.file_path, *values, @test_url.call(test) ]
      end
    end

    def flaky_rows
      FlakyRanking.new(@project, @filter, now: @now).rows(limit: LIMIT).map do |row|
        test = row.test_case
        [ test.id, test.full_name, test.file_path, row.flip_rate, row.reason, row.flaky_since_build&.id, row.sample_count,
          row.quarantined, @test_url.call(test) ]
      end
    end

    def file_rows
      FileRanking.new(@project, @filter, now: @now).rows(limit: LIMIT).map do |row|
        [ row.file_path, row.tests, row.executed, row.failures, row.failure_rate, row.total_duration_ms ]
      end
    end

    def trend_rows
      Trend.new(@project, @filter, now: @now).points.map do |point|
        [ point.date, point.executed, point.failed, point.failure_rate, point.avg_test_duration_ms, point.avg_build_duration_ms,
          point.flaky_count ]
      end
    end
  end
end
