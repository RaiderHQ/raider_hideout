module Flakiness
  Sample = Data.define(:status, :commit_sha, :retried_flaky)
  Verdict = Data.define(:flaky, :reason, :flip_rate)

  class Analyzer
    WINDOW = 20
    MIN_SAMPLES = 5
    MIN_FLIPS = 2
    FLIP_THRESHOLD = 0.15
    EXECUTED = %w[passed failed quarantined].freeze

    def self.call(samples)
      new(samples).call
    end

    # A quarantined result failed; it only did not fail the build (spec §5.1).
    def initialize(samples)
      @samples = samples.map { |s| s.status == "quarantined" ? s.with(status: "failed") : s }
      @executed = @samples.select { |s| EXECUTED.include?(s.status) }
    end

    def call
      Verdict.new(flaky: !reason.nil?, reason: reason, flip_rate: flip_rate.round(4))
    end

    private

    def reason
      @reason ||= if same_commit? then "same_commit"
      elsif @samples.any?(&:retried_flaky) then "retry"
      elsif frequent_flips? then "flips"
      end
    end

    def flips
      @flips ||= @executed.each_cons(2).count { |a, b| a.status != b.status }
    end

    def flip_rate
      @executed.size > 1 ? flips.fdiv(@executed.size - 1) : 0.0
    end

    def frequent_flips?
      @executed.size >= MIN_SAMPLES && flips >= MIN_FLIPS && flip_rate >= FLIP_THRESHOLD
    end

    def same_commit?
      @executed.reject { |s| s.commit_sha.blank? }.group_by(&:commit_sha)
               .any? { |_sha, group| group.map(&:status).uniq.size == 2 }
    end
  end
end
