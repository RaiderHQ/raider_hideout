class ExploreController < ApplicationController
  FIELD_KEYS = %i[text name file error branch tags since flaky quarantined sort].freeze

  def show
    @view = SavedView.visible_to(Current.user, current_project).find(params[:view].to_s) if params[:view].present?
    return redirect_to_canonical if params[:fields] == "1"

    @level = params[:level].presence_in(Search::Filter::LEVELS) || @view&.level || "tests"
    # An explicit q (even empty) wins over the view's query, so clearing every filter clears it.
    @filter = Search::Filter.parse(params.key?(:q) ? params[:q].to_s : @view&.query.to_s)
    @modified = @view.present? && (@view.level != @level || Search::Filter.parse(@view.query) != @filter)
    query = (@level == "results" ? Search::ResultsQuery : Search::TestsQuery).new(current_project, @filter)
    @branch = query.branch
    paginate(query.count)
    @rows = query.page(limit: @pagy.limit, offset: @pagy.offset)
    @branches = branches
    @views = SavedView.visible_to(Current.user, current_project).order(:name).to_a
  end

  private

  # The fields form and the query box show one filter: field submissions are printed
  # back as the canonical query string so the URL is the single source (spec §4.5).
  def redirect_to_canonical
    level = params[:level].presence_in(Search::Filter::LEVELS) || "tests"
    fields = params.slice(*FIELD_KEYS, :statuses).permit(*FIELD_KEYS, statuses: [])
    filter = Search::Filter.from_params(fields, default_branch: current_project.default_branch, level: level)
    redirect_to project_explore_path(current_project, **canonical_params(level, filter)), status: :see_other
  end

  def canonical_params(level, filter)
    { level: level, q: filter.to_query, view: @view&.id }.compact
  end

  def branches
    recent = current_project.runs.where(created_at: Search::Filter::RANGES.fetch("90d").ago..)
                            .where.not(branch: [ nil, "" ]).distinct.pluck(:branch)
    (recent | [ @branch ]).sort
  end

  # Pagy over the row count; the page number is clamped into range.
  def paginate(count)
    per = Search::BaseQuery::PER_PAGE
    last = [ (count / per.to_f).ceil, 1 ].max
    @pagy = Pagy::Offset.new(count: count, page: params[:page].to_s.to_i.clamp(1, last), limit: per,
                             request: Pagy::Request.new(request: request))
  end
end
