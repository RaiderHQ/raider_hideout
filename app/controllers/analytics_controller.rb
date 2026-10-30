# The project's Analytics page (spec 2026-10-28 §4): ranked fix lists, headline numbers and
# trends over one branch and window, and each list as CSV. Every member of the project's
# organization may view and export it.
class AnalyticsController < ApplicationController
  PAGE_ROWS = 10

  def show
    @filter = Analytics::Filter.parse(params[:q].to_s, default_branch: current_project.default_branch)
    @now = Time.current
    respond_to do |format|
      format.html { load_page }
      format.csv { send_list }
    end
  end

  private

  def load_page
    @headline = Analytics::Headline.new(current_project, @filter, now: @now)
    @no_activity = @headline.empty? && !Analytics::Query.new(current_project, @filter, now: @now).any_executed?
    @failing = Analytics::TestRanking.new(current_project, @filter, mode: "failing", now: @now).rows(limit: PAGE_ROWS)
    @slowest = Analytics::TestRanking.new(current_project, @filter, mode: "slowest", now: @now).rows(limit: PAGE_ROWS)
    @flaky = Analytics::FlakyRanking.new(current_project, @filter, now: @now).rows(limit: PAGE_ROWS)
    @files = Analytics::FileRanking.new(current_project, @filter, now: @now).rows(limit: PAGE_ROWS)
    @trend = Analytics::Trend.new(current_project, @filter, now: @now)
  end

  # An unknown list is a 404 (ApplicationController renders it as head :not_found for CSV).
  def send_list
    list = params[:list].to_s
    raise ActiveRecord::RecordNotFound unless Analytics::Csv::LISTS.include?(list)

    branch = @filter.branch
    csv = Analytics::Csv.new(current_project, @filter, list: list, now: @now,
                             test_url: ->(test_case) { project_test_case_url(current_project, test_case, branch: branch) })
    response.headers["Cache-Control"] = "no-store"
    send_data csv.to_csv, type: "text/csv", filename: csv.filename, disposition: "attachment"
  end
end
