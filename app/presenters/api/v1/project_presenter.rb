module Api
  module V1
    # §5.1 project fields.
    class ProjectPresenter < BasePresenter
      HEALTH_DAYS = 30
      TOP_ERROR_GROUPS = 5
      RECENT_BUILDS = 10
      # The API's own cut; ErrorGroup::SAMPLE_MESSAGE_LIMIT (10_000) is the storage limit.
      SAMPLE_MESSAGE_LIMIT = 300

      def initialize(project, url_options:)
        super(url_options: url_options)
        @project = project
      end

      def to_h
        latest = @project.latest_build
        {
          slug: @project.slug,
          name: @project.name,
          organization: { slug: @project.organization.slug, name: @project.organization.name },
          default_branch: @project.default_branch,
          latest_build: latest && {
            id: latest.id, status: latest.status, pass_rate: latest.pass_rate, gate_status: latest.gate_report.state,
            branch: latest.branch, created_at: time(latest.created_at)
          },
          url: url(:project_url, @project)
        }
      end

      # §5.2: every health field covers the default branch over the last 30 days.
      def detail(now: Time.current)
        branch = @project.default_branch
        since = now - HEALTH_DAYS.days
        in_range = @project.builds.where(branch: branch, created_at: since..)
        rated = in_range.select(:id, :passed_count, :failed_count, :quarantined_count).to_a
        to_h.merge(health: {
          builds: rated.size,
          pass_rate: @project.average_pass_rate(rated),
          flaky_count: @project.flaky_count,
          quarantined_count: @project.quarantines.active(now).count,
          top_error_groups: top_error_groups(branch, since),
          recent_builds: in_range.includes(:project).order(created_at: :desc, id: :desc).limit(RECENT_BUILDS)
                                 .map { |build| BuildPresenter.new(build, url_options: @url_options).to_h }
        })
      end

      private

      # Groups of the failing results in range, by distinct affected tests.
      def top_error_groups(branch, since)
        rows = TestResult.joins(:run)
                         .where(runs: { project_id: @project.id, branch: branch, created_at: since.. },
                                status: TestResult::FAILING_STATUSES)
                         .where.not(error_group_id: nil)
                         .group(:error_group_id)
                         .order(Arel.sql("COUNT(DISTINCT test_results.test_case_id) DESC"), :error_group_id)
                         .limit(TOP_ERROR_GROUPS)
                         .pluck(:error_group_id, Arel.sql("COUNT(DISTINCT test_results.test_case_id)"))
        groups = @project.error_groups.where(id: rows.map(&:first)).index_by(&:id)
        rows.filter_map do |id, affected|
          group = groups[id]
          group && { id: id, exception_class: group.exception_class,
                     sample_message: clip(group.sample_message, SAMPLE_MESSAGE_LIMIT), affected_tests: affected }
        end
      end
    end
  end
end
