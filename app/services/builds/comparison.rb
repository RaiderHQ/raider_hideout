module Builds
  # Compares a build with its frozen baseline. A test's status in a build is the
  # worst of its results: failed, else passed, else not run.
  class Comparison
    FAILED = 2
    PASSED = 1
    STATUS_SQL = "MAX(CASE status WHEN 'failed' THEN 2 WHEN 'passed' THEN 1 ELSE 0 END)".freeze
    BUCKETS = %i[new_failures still_failing fixed new_tests].freeze

    def initialize(build)
      @build = build
    end

    def baseline
      @build.baseline_build
    end

    def available?
      baseline.present?
    end

    def branch
      baseline&.branch
    end

    BUCKETS.each do |name|
      define_method(name) { buckets[name] }
    end

    def counts
      BUCKETS.index_with { |name| buckets[name].size }
    end

    def expired?
      return @expired if defined?(@expired)

      @expired = available? && baseline.results_expired?
    end

    def status_for(test_case_id)
      return unless available? && !expired?

      case [ current[test_case_id], previous[test_case_id] ]
      in [ FAILED, FAILED ] then :still_failing
      in [ FAILED, _ ] then :new_failure
      else nil
      end
    end

    def new_test?(test_case_id)
      available? && !expired? && current.key?(test_case_id) && !previous.key?(test_case_id)
    end

    private

    def current
      @current ||= statuses(@build)
    end

    def previous
      @previous ||= statuses(baseline)
    end

    def statuses(build)
      TestResult.where(run_id: build.runs.select(:id)).group(:test_case_id).pluck(:test_case_id, Arel.sql(STATUS_SQL)).to_h
    end

    def buckets
      @buckets ||= available? && !expired? ? build_buckets : BUCKETS.index_with { [] }
    end

    def build_buckets
      ids = BUCKETS.index_with { [] }
      current.each do |id, now|
        before = previous[id]
        ids[:new_failures] << id if now == FAILED && before != FAILED
        ids[:still_failing] << id if now == FAILED && before == FAILED
        ids[:fixed] << id if now == PASSED && before == FAILED
        ids[:new_tests] << id if before.nil?
      end
      cases = TestCase.where(id: ids.values.flatten.uniq).index_by(&:id)
      ids.transform_values { |list| list.filter_map { |id| cases[id] }.sort_by { |tc| [ tc.file_path.to_s, tc.full_name.to_s ] } }
    end
  end
end
