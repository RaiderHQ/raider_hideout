module Api
  module V1
    module Public
      # The read side of the personal-token API and the MCP tools (spec §5, §6): one method per
      # endpoint, taking the request's parameters and returning the response Hash. Every lookup
      # starts from the user's projects, so other organizations' records are never found.
      class Reader
        class NotFound < StandardError; end

        # details: one message per bad parameter; REST renders them, MCP shows the message.
        class InvalidParams < StandardError
          attr_reader :details

          def initialize(details)
            @details = details
            super("Invalid arguments: #{details.join('; ')}")
          end
        end

        Paging = Data.define(:page, :per_page) do
          def offset = (page - 1) * per_page
        end

        DEFAULT_PER_PAGE = 50
        MAX_PER_PAGE = 100
        # Keeps page * per_page inside the database's integer range (an overflow is a 500).
        MAX_PAGE = 2_147_483_647
        BUILD_STATUSES = %w[passed failed incomplete].freeze
        RANGES = Search::Filter::RANGES
        DEFAULT_ERROR_RANGE = "30d".freeze
        # Newest build time per project. A constant: no user input, so nothing to bind.
        LATEST_BUILDS_JOIN = <<~SQL.squish.freeze
          LEFT JOIN (SELECT project_id, MAX(created_at) AS latest_at FROM builds GROUP BY project_id) latest_builds
          ON latest_builds.project_id = projects.id
        SQL
        PROJECT_ORDER = Arel.sql("CASE WHEN latest_builds.latest_at IS NULL THEN 1 ELSE 0 END, " \
                                 "latest_builds.latest_at DESC, projects.name ASC, projects.id ASC")

        def initialize(user:, base_url:, now: Time.current)
          @user = user
          @url_options = { host: base_url }
          @now = now
        end

        # §5.1
        def projects(params = {})
          params = options(params)
          errors = []
          paging = paging(params, errors)
          raise InvalidParams, errors if errors.any?

          scope = @user.projects
          rows = scope.includes(:organization).joins(LATEST_BUILDS_JOIN).order(PROJECT_ORDER)
                      .limit(paging.per_page).offset(paging.offset)
          list(rows.map { |project| ProjectPresenter.new(project, url_options: @url_options).to_h }, paging, scope.count)
        end

        # §5.2
        def project(slug)
          ProjectPresenter.new(find_project(slug), url_options: @url_options).detail(now: @now)
        end

        # §5.3
        def builds(slug, params = {})
          project = find_project(slug)
          params = options(params)
          errors = []
          paging = paging(params, errors)
          status = choice(params[:status], BUILD_STATUSES, "status", errors)
          since = choice(params[:since], RANGES.keys, "since", errors)
          raise InvalidParams, errors if errors.any?

          scope = project.builds
          scope = scope.where(branch: params[:branch].to_s) if params[:branch].present?
          scope = scope.where(status: status) if status
          scope = scope.where(created_at: (@now - RANGES.fetch(since))..) if since
          rows = scope.includes(:project).order(created_at: :desc, id: :desc).limit(paging.per_page).offset(paging.offset)
          list(rows.map { |build| BuildPresenter.new(build, url_options: @url_options).to_h }, paging, scope.count)
        end

        # §5.4: id is a build id or "latest" (the newest build on params[:branch], default the default branch).
        def build(slug, id, params = {})
          project = find_project(slug)
          build = find_build(project, id.to_s, options(params)[:branch].presence)
          BuildPresenter.new(build, url_options: @url_options).detail
        end

        # §5.5: q is Explore syntax; its notices come back verbatim and never fail the request.
        def test_cases(slug, params = {})
          project = find_project(slug)
          params = options(params)
          errors = []
          paging = paging(params, errors)
          raise InvalidParams, errors if errors.any?

          filter = Search::Filter.parse(params[:q].to_s)
          query = Search::TestsQuery.new(project, filter, now: @now)
          rows = query.page(limit: paging.per_page, offset: paging.offset)
          quarantined = quarantined_case_ids(project, rows.map { |row| row.test_case.id })
          data = rows.map do |row|
            TestCasePresenter.new(row.test_case, url_options: @url_options).row(row, quarantined: quarantined.include?(row.test_case.id))
          end
          list(data, paging, query.count, query: filter.to_query, notices: filter.notices)
        end

        # §5.6
        def test_case(slug, id)
          project = find_project(slug)
          test_case = find_record(project.test_cases, id) || raise(NotFound, "No test #{id} in project '#{project.slug}'.")
          row = Search::TestsQuery.new(project, Search::Filter.new, now: @now).row_for(test_case)
          quarantine = test_case.quarantines.active(@now).includes(:created_by).first
          TestCasePresenter.new(test_case, url_options: @url_options).detail(row, quarantine: quarantine)
        end

        # §5.7
        def error_groups(slug, params = {})
          project = find_project(slug)
          params = options(params)
          errors = []
          paging = paging(params, errors)
          since = choice(params[:since], RANGES.keys, "since", errors) || DEFAULT_ERROR_RANGE
          raise InvalidParams, errors if errors.any?

          start = @now - RANGES.fetch(since)
          scope = project.error_groups.where(last_seen_at: start..)
          groups = scope.order(last_seen_at: :desc, id: :desc).limit(paging.per_page).offset(paging.offset).to_a
          affected = affected_tests(project, groups.map(&:id), since: start)
          data = groups.map do |group|
            ErrorGroupPresenter.new(group, url_options: @url_options).to_h(affected_tests: affected.fetch(group.id, 0))
          end
          list(data, paging, scope.count)
        end

        # §5.8
        def error_group(slug, id)
          project = find_project(slug)
          group = find_record(project.error_groups, id) ||
                  raise(NotFound, "No error group #{id} in project '#{project.slug}'.")
          affected = affected_tests(project, [ group.id ]).fetch(group.id, 0)
          ErrorGroupPresenter.new(group, url_options: @url_options).detail(affected_tests: affected)
        end

        # §5.9
        def flaky_tests(slug, params = {})
          project = find_project(slug)
          params = options(params)
          errors = []
          paging = paging(params, errors)
          raise InvalidParams, errors if errors.any?

          scope = TestCaseVerdict.flaky_on(project, params[:branch].presence || project.default_branch)
          verdicts = scope.includes(:test_case).limit(paging.per_page).offset(paging.offset)
          list(verdicts.map { |verdict| TestCasePresenter.new(verdict.test_case, url_options: @url_options).flaky(verdict) },
               paging, scope.count)
        end

        # §5.10
        def quarantines(slug, params = {})
          project = find_project(slug)
          params = options(params)
          errors = []
          paging = paging(params, errors)
          raise InvalidParams, errors if errors.any?

          scope = project.quarantines.active(@now)
          rows = scope.includes(:test_case, :created_by).order(:expires_at, :id).limit(paging.per_page).offset(paging.offset)
          list(rows.map { |quarantine| QuarantinePresenter.new(quarantine, url_options: @url_options).to_h }, paging, scope.count)
        end

        private

        def options(params)
          params.to_h.transform_keys(&:to_sym)
        end

        def paging(params, errors)
          page = whole(params[:page], 1)
          per_page = whole(params[:per_page], DEFAULT_PER_PAGE)
          errors << "page must be an integer of at least 1" unless page&.between?(1, MAX_PAGE)
          errors << "per_page must be an integer from 1 to #{MAX_PER_PAGE}" unless per_page&.between?(1, MAX_PER_PAGE)
          Paging.new(page: page.to_i, per_page: per_page.to_i)
        end

        # nil and "" mean the default; anything else must be a whole number (nil when it is not).
        def whole(value, default)
          return default if value.nil? || value == ""
          return value if value.is_a?(Integer)

          Integer(value.to_s, 10, exception: false)
        end

        def list(data, paging, total, **meta)
          next_page = paging.page * paging.per_page < total ? paging.page + 1 : nil
          { data: data, meta: { page: paging.page, per_page: paging.per_page, total: total, next_page: next_page, **meta } }
        end

        def find_project(slug)
          @user.projects.includes(:organization).find_by(slug: slug.to_s) ||
            raise(NotFound, "No project '#{slug}'. Call list_projects for the slugs you can see.")
        end

        # nil and "" mean "not given"; anything else must be one of allowed.
        def choice(value, allowed, name, errors)
          return nil if value.nil? || value == ""
          return value if allowed.include?(value)

          errors << "#{name} must be one of #{allowed.join(', ')}"
          nil
        end

        def find_build(project, id, branch)
          builds = project.builds.includes(:project)
          if id == "latest"
            branch ||= project.default_branch
            builds.where(branch: branch).order(created_at: :desc, id: :desc).first ||
              raise(NotFound, "No builds on branch '#{branch}' in project '#{project.slug}'.")
          elsif id.match?(/\A\d+\z/)
            builds.find_by(id: id.to_i) || raise(NotFound, "No build #{id} in project '#{project.slug}'.")
          else
            raise InvalidParams, [ %(build_id must be an integer or "latest") ]
          end
        end

        # A loose id such as "12abc" must not be cast to 12 by the database layer.
        def find_record(scope, id)
          scope.find_by(id: id.to_i) if id.to_s.match?(/\A\d+\z/)
        end

        def quarantined_case_ids(project, ids)
          project.quarantines.active(@now).where(test_case_id: ids).pluck(:test_case_id).to_set
        end

        # Distinct tests with failing results, per group; only results since the given time when one is given.
        def affected_tests(project, group_ids, since: nil)
          scope = TestResult.joins(:run).where(error_group_id: group_ids, status: TestResult::FAILING_STATUSES,
                                               runs: { project_id: project.id })
          scope = scope.where(runs: { created_at: since.. }) if since
          scope.group(:error_group_id).distinct.count(:test_case_id)
        end
      end
    end
  end
end
