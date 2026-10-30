class SavedViewsController < ApplicationController
  SHARE_DENIED = "You need the member role or higher to share views.".freeze

  before_action :set_view, only: %i[update destroy]
  before_action :require_editable, only: %i[update destroy]

  def create
    attrs = view_params
    view = current_project.saved_views.new(user: Current.user, name: attrs[:name], level: attrs[:level],
                                           query: canonical(attrs[:q]), shared: attrs[:shared] == "1")
    return back_to_search(attrs, SHARE_DENIED) if view.shared? && !role_at_least?(:member)
    return back_to_search(attrs, view.errors.full_messages.to_sentence) unless view.save

    redirect_to project_explore_path(current_project, view: view.id), notice: "View saved."
  end

  def update
    attrs = view_params
    changes = { name: attrs[:name], level: attrs[:level] }.compact
    changes[:query] = canonical(attrs[:q]) if attrs.key?(:q)
    if attrs.key?(:shared) && (attrs[:shared] == "1") != @view.shared?
      return redirect_to project_explore_path(current_project, view: @view.id), alert: SHARE_DENIED unless role_at_least?(:member)

      changes[:shared] = attrs[:shared] == "1"
    end
    if @view.update(changes)
      redirect_to project_explore_path(current_project, view: @view.id), notice: "View updated."
    else
      redirect_to project_explore_path(current_project, view: @view.id), alert: @view.errors.full_messages.to_sentence
    end
  end

  def destroy
    @view.destroy!
    redirect_to project_explore_path(current_project), notice: "View deleted."
  end

  private

  # A view the user may not see is a 404 (spec §5.3).
  def set_view
    @view = SavedView.visible_to(Current.user, current_project).find(params[:id])
  end

  def require_editable
    return if @view.editable_by?(Current.user, current_role)

    @required_role = "admin"
    render "errors/forbidden", status: :forbidden
  end

  def view_params
    params.expect(saved_view: %i[name level q shared])
  end

  def canonical(query) = Search::Filter.parse(query.to_s).to_query

  def back_to_search(attrs, alert)
    level = attrs[:level].presence_in(Search::Filter::LEVELS) || "tests"
    redirect_to project_explore_path(current_project, level: level, q: canonical(attrs[:q])), alert: alert
  end
end
