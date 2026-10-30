module Builds
  # Freezes the build a build is compared with: the newest complete build on its
  # comparison branch that was created before it. Assigned once, when the build is
  # ready to notify; later builds on that branch never move it.
  class Baseline
    CANDIDATE_LIMIT = 50

    def self.assign!(build)
      new(build).assign!
    end

    def initialize(build)
      @build = build
    end

    def assign!
      return if @build.baseline_assigned_at

      # Atomic claim: only one concurrent caller can flip the unassigned row. update_all
      # skips the card broadcast on purpose; the build card shows nothing about the baseline.
      now = Time.current
      Build.where(id: @build.id, baseline_assigned_at: nil, baseline_build_id: nil)
           .update_all(baseline_build_id: find&.id, baseline_assigned_at: now, updated_at: now)
      @build.reload
      nil
    end

    private

    def find
      branch = @build.comparison_branch
      return if branch.blank?

      earlier = Build.arel_table
      before = earlier[:created_at].lt(@build.created_at)
                 .or(earlier[:created_at].eq(@build.created_at).and(earlier[:id].lt(@build.id)))
      scope = @build.project.builds.where(branch: branch).where(before)
      # CI builds compare with CI builds; synthetic (local run) builds may use either.
      scope = scope.where.not("builds.build_key LIKE ?", "run:%") unless @build.synthetic?
      scope = scope.where.not(Run.where("runs.build_id = builds.id").where.not(results_purged_at: nil).arel.exists)
      scope.order(created_at: :desc, id: :desc).limit(CANDIDATE_LIMIT).find(&:complete?)
    end
  end
end
