module Notifications
  module Rules
    CANDIDATES = 20

    def self.call(channel, build)
      events = []
      events << "failed" if channel.on_failed && build.status == "failed"
      events << "recovered" if channel.on_recovered && build.status == "passed" && previous_failed?(build)
      events << "new_flaky" if channel.on_new_flaky && new_flaky?(build)
      events << "low_pass_rate" if low_pass_rate?(channel, build)
      events
    end

    def self.previous_failed?(build)
      previous = build.project.builds.where(branch: build.branch)
                      .where("created_at < :t OR (created_at = :t AND id < :id)", t: build.created_at, id: build.id)
                      .order(created_at: :desc, id: :desc).limit(CANDIDATES).detect(&:complete?)
      previous.present? && previous.status == "failed"
    end

    def self.new_flaky?(build)
      new_flaky_scope(build).exists?
    end

    # Verdicts on the build's branch that turned flaky in this build.
    def self.new_flaky_scope(build)
      TestCaseVerdict.where(branch: build.branch, flaky: true, flaky_since_build_id: build.id)
    end

    def self.low_pass_rate?(channel, build)
      rate = build.pass_rate
      channel.pass_rate_below.present? && rate && rate < channel.pass_rate_below
    end
  end
end
