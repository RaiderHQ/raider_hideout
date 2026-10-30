module Analytics
  # One project's builds on a branch in a time range as light tuples, oldest first (spec
  # 2026-10-28 §5). Builds are kept forever, so these numbers outlive result retention;
  # file: and tag: never apply to them.
  module BuildPoints
    Point = Struct.new(:id, :created_at, :passed, :failed, :quarantined, :duration_ms, :flaky_count, keyword_init: true) do
      def pass_rate = Build.pass_rate_for(passed: passed, failed: failed, quarantined: quarantined)
    end

    def self.in(project, branch:, range:)
      project.builds.where(branch: branch, created_at: range).order(:created_at, :id)
             .pluck(:id, :created_at, :passed_count, :failed_count, :quarantined_count, :duration_ms, :flaky_count)
             .map do |id, created_at, passed, failed, quarantined, duration, flaky|
               Point.new(id: id, created_at: created_at, passed: passed, failed: failed, quarantined: quarantined,
                         duration_ms: duration, flaky_count: flaky)
             end
    end

    # The project page's averages (Project#average_pass_rate, #average_duration_ms): nil values skipped.
    def self.average(values)
      present = values.compact
      present.any? ? (present.sum.to_f / present.size).round : nil
    end
  end
end
