module Analytics
  # Four build numbers over the window on the branch, each with its change against the
  # previous window of the same length (spec 2026-10-28 §4.3). branch: and since: only.
  class Headline
    Number = Struct.new(:value, :delta, keyword_init: true)
    NO_DATA = "—".freeze

    def initialize(project, filter, now: Time.current)
      start = filter.range_start(now)
      @current = BuildPoints.in(project, branch: filter.branch, range: start..)
      @previous = BuildPoints.in(project, branch: filter.branch, range: (start - filter.length)...start)
    end

    def empty? = @current.empty?

    def builds = number(:count, :percent)

    def pass_rate = number(:pass_rate, :points)

    def avg_duration_ms = number(:duration, :percent)

    def flaky = number(:flaky, :count)

    private

    def number(metric, kind)
      value = value_of(metric, @current)
      previous = value_of(metric, @previous) unless @previous.empty?
      Number.new(value: value, delta: delta(value, previous, kind))
    end

    def value_of(metric, points)
      case metric
      when :count then points.size
      when :pass_rate then BuildPoints.average(points.map(&:pass_rate))
      when :duration then BuildPoints.average(points.map(&:duration_ms))
      when :flaky then points.last&.flaky_count
      end
    end

    def delta(value, previous, kind)
      return NO_DATA if value.nil? || previous.nil? || (kind == :percent && previous.zero?)

      case kind
      when :percent then change(((value - previous) * 100.0 / previous).round, "%")
      when :points then change(value - previous, (value - previous).abs == 1 ? " pt" : " pts")
      when :count then change(value - previous, "")
      end
    end

    def change(diff, unit)
      return "0#{unit}" if diff.zero?

      "#{diff.positive? ? '▲' : '▼'} #{diff.abs}#{unit}"
    end
  end
end
