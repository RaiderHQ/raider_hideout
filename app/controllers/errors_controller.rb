class ErrorsController < ApplicationController
  WINDOWS = [ 7, 14, 30, 90 ].freeze
  DEFAULT_WINDOW = 14
  PER_PAGE = 25
  AFFECTED_TESTS_LIMIT = 50
  RECENT_BUILDS_LIMIT = 20

  def index
    @windows = windows
    window = params[:window].to_s.to_i
    @window = if @windows.include?(window) then window
    elsif @windows.include?(DEFAULT_WINDOW) then DEFAULT_WINDOW
    else @windows.max
    end
    in_window = failed_results.where(runs: { created_at: @window.days.ago.. })
    @branches = in_window.where.not(runs: { branch: nil }).distinct.order("runs.branch").pluck("runs.branch")
    @branch = params[:branch].presence_in(@branches)
    scope = @branch ? in_window.where(runs: { branch: @branch }) : in_window
    paginate(scope.distinct.count(:error_group_id))
    page_rows = scope.group(:error_group_id)
                     .order(Arel.sql("COUNT(*) DESC"), :error_group_id)
                     .limit(@pagy.limit).offset(@pagy.offset)
                     .pluck(:error_group_id, Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT test_results.test_case_id)"),
                            Arel.sql("COUNT(DISTINCT runs.build_id)"), Arel.sql("MAX(runs.created_at)"))
    groups = current_project.error_groups.where(id: page_rows.map(&:first)).index_by(&:id)
    @rows = page_rows.map do |id, failures, tests, builds, last_seen|
      { group: groups.fetch(id), failures: failures, tests: tests, builds: builds, last_seen: parse_time(last_seen) }
    end
  end

  def show
    @group = current_project.error_groups.find(params[:id])
    results = @group.test_results.where(status: TestResult::FAILING_STATUSES)
    @sample = results.order(created_at: :desc, id: :desc).first
    affected = results.joins(:run).group(:test_case_id).order(Arel.sql("COUNT(*) DESC"), :test_case_id).limit(AFFECTED_TESTS_LIMIT)
                      .pluck(:test_case_id, Arel.sql("COUNT(*)"), Arel.sql("MAX(runs.created_at)"))
    cases = current_project.test_cases.where(id: affected.map(&:first)).index_by(&:id)
    @affected = affected.map { |id, failures, last| { test_case: cases.fetch(id), failures: failures, last_failed: parse_time(last) } }
    recent = results.joins(:run).group("runs.build_id").order(Arel.sql("MAX(runs.created_at) DESC"), Arel.sql("runs.build_id DESC"))
                    .limit(RECENT_BUILDS_LIMIT).pluck("runs.build_id", Arel.sql("MAX(runs.created_at)"))
    builds = current_project.builds.where(id: recent.map(&:first)).index_by(&:id)
    @recent_builds = recent.map { |id, seen| { build: builds.fetch(id), seen: parse_time(seen) } }
  end

  private

  # Windows longer than the result retention would silently show less data than they claim.
  def windows
    max = Retention.config.result_days
    offered = WINDOWS.select { |days| days <= max }
    offered.empty? ? [ max ] : offered
  end

  def failed_results
    TestResult.joins(:run).where(runs: { project_id: current_project.id },
                                         error_group_id: current_project.error_groups.select(:id), status: TestResult::FAILING_STATUSES)
  end

  # Pagy over the group count; the page number is clamped into range.
  def paginate(count)
    last = [ (count / PER_PAGE.to_f).ceil, 1 ].max
    @pagy = Pagy::Offset.new(count: count, page: params[:page].to_s.to_i.clamp(1, last), limit: PER_PAGE,
                             request: Pagy::Request.new(request: request))
  end

  def parse_time(value)
    value.is_a?(String) ? Time.zone.parse("#{value} UTC") : value
  end
end
