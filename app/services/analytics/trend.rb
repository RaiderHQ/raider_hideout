module Analytics
  # Day buckets for 7d and 30d, ISO week buckets (Monday) for 90d, in Time.zone, covering
  # the whole window (spec 2026-10-28 §4.5). SQL aggregates per run; buckets are formed in
  # Ruby so the SQL is the same on SQLite and Postgres. An empty bucket is nil, not zero.
  class Trend < Query
    Point = Struct.new(:date, :executed, :failed, :failure_rate, :avg_test_duration_ms, :avg_build_duration_ms, :flaky_count,
                       keyword_init: true)

    def initialize(project, filter, now: Time.current)
      super
      @weekly = filter.since == "90d"
    end

    def weekly? = @weekly

    def points
      @points ||= begin
        runs = run_totals.group_by { |time, *| bucket(time) }
        builds = BuildPoints.in(@project, branch: branch, range: range_start..).group_by { |point| bucket(point.created_at) }
        dates.map { |date| point(date, runs.fetch(date, []), builds.fetch(date, [])) }
      end
    end

    private

    def range_start = @filter.range_start(@now)

    def dates
      (bucket(range_start)..bucket(@now)).step(@weekly ? 7 : 1).to_a
    end

    def bucket(time)
      date = time.in_time_zone.to_date
      @weekly ? date.beginning_of_week(:monday) : date
    end

    # [created_at, executed, failing, duration sum] per run in the window.
    def run_totals
      executed.group("runs.id")
              .pluck(Arel.sql("MAX(runs.created_at)"), Arel.sql("COUNT(*)"), Arel.sql(FAILED), Arel.sql("SUM(test_results.duration_ms)"))
              .map { |time, count, failed, sum| [ parse_time(time), count.to_i, failed.to_i, sum.to_i ] }
    end

    def point(date, runs, builds)
      count = runs.sum { |_, executed, *| executed }
      failed = runs.sum { |_, _, failing, _| failing }
      duration = runs.sum { |*, sum| sum }
      Point.new(date: date, executed: count, failed: failed, failure_rate: self.class.floored_rate(failed, count),
                avg_test_duration_ms: count.positive? ? (duration.to_f / count).round : nil,
                avg_build_duration_ms: BuildPoints.average(builds.map(&:duration_ms)), flaky_count: builds.last&.flaky_count)
    end
  end
end
