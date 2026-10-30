require "rails_helper"

RSpec.describe "Explore", type: :request do
  let(:owner) { create(:user) }
  let(:organization) { create(:organization).tap { create(:membership, organization: _1, user: owner, role: "owner") } }
  let(:project) { create(:project, organization: organization) }

  def member(role)
    create(:user).tap { create(:membership, organization: organization, user: _1, role: role) }
  end

  def tc(name) = create(:test_case, project: project, full_name: name)

  before do
    search_result(tc("Login works"), status: "failed", tags: [ "smoke" ], message: "Net::ReadTimeout", exception: "Net::ReadTimeout")
    search_result(tc("Cart totals"), status: "passed")
  end

  %w[viewer member admin].each do |role|
    it "shows the tests level to a #{role}" do
      sign_in(member(role))
      get project_explore_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Login works", "Cart totals")
    end
  end

  it "filters by the query box and keeps the query in the box" do
    sign_in(owner)
    get project_explore_path(project, q: "status:failed tag:smoke")
    expect(response.body).to include("Login works")
    expect(response.body).not_to include("Cart totals")
    expect(response.body).to include('value="status:failed tag:smoke"')
  end

  it "shows the results level" do
    sign_in(owner)
    get project_explore_path(project, level: "results", q: 'error:"ReadTimeout"')
    expect(response.body).to include("Login works", "Net::ReadTimeout")
    expect(response.body).not_to include("Cart totals")
  end

  it "redirects a fields submission to the canonical query" do
    sign_in(owner)
    get project_explore_path(project, fields: "1", level: "results", statuses: %w[failed], tags: "Smoke", branch: "main",
                                      since: "7d", sort: "recent", text: "login")
    expect(response).to have_http_status(:see_other)
    expect(response).to redirect_to(project_explore_path(project, level: "results", q: "login status:failed tag:smoke"))
  end

  it "shows notices for ignored parts and still runs" do
    sign_in(owner)
    get project_explore_path(project, q: "foo:bar status:failed")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ignored &quot;foo:bar&quot;: unknown filter", "Login works")
  end

  it "falls back on an unknown level and clamps a page past the end" do
    sign_in(owner)
    get project_explore_path(project, level: "bogus", page: 99)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Login works")
  end

  it "explains an empty search" do
    sign_in(owner)
    get project_explore_path(project, q: "branch:nowhere")
    expect(response.body).to include("No tests ran on nowhere in the last 7 days.", "Clear filters")
    get project_explore_path(project, q: "name:zzz")
    expect(response.body).to include("No tests match.")
    get project_explore_path(project, level: "results", q: "name:zzz")
    expect(response.body).to include("No results match.")
  end

  it "404s for another organization's project" do
    sign_in(create(:user))
    get project_explore_path(project)
    expect(response).to have_http_status(:not_found)
  end

  it "is linked from the project page and the error group page" do
    sign_in(owner)
    get project_path(project)
    expect(response.body).to include(project_explore_path(project))
    group = ErrorGroup.create!(project: project, digest: "d", exception_class: "Net::ReadTimeout", normalized_message: "m",
                               first_seen_at: Time.current, last_seen_at: Time.current)
    get project_error_path(project, group)
    expect(response.body).to include(CGI.escapeHTML(project_explore_path(project, level: "results", q: Search::Filter.new(error: "Net::ReadTimeout", since: "30d").to_query)))
  end

  describe "saved views" do
    it "opens a view with its query and level, and marks it modified when the filter changes" do
      view = create(:saved_view, project: project, user: owner, name: "Smoke fails", query: "status:failed tag:smoke", level: "tests")
      sign_in(owner)
      get project_explore_path(project, view: view.id)
      expect(response.body).to include("Smoke fails", 'value="status:failed tag:smoke"', "Login works")
      expect(response.body).not_to include("Cart totals", "Modified")

      get project_explore_path(project, view: view.id, level: "tests", q: "status:passed")
      expect(response.body).to include("Modified", "Cart totals")
    end

    it "shows the unfiltered search when a view's filters are all cleared" do
      view = create(:saved_view, project: project, user: owner, query: "status:failed")
      sign_in(owner)
      get project_explore_path(project, view: view.id, level: "tests", q: "")
      expect(response.body).to include("Login works", "Cart totals")
    end

    it "keeps the view when the fields form is submitted" do
      view = create(:saved_view, project: project, user: owner, query: "status:failed")
      sign_in(owner)
      get project_explore_path(project, view: view.id, fields: "1", level: "tests", statuses: %w[passed])
      expect(response).to redirect_to(project_explore_path(project, level: "tests", q: "status:passed", view: view.id))
    end

    it "lists my views and others' shared views, not others' personal views" do
      create(:saved_view, project: project, user: owner, name: "My view")
      other = member("member")
      create(:saved_view, project: project, user: other, name: "Team view", shared: true)
      create(:saved_view, project: project, user: other, name: "Their secret")
      sign_in(owner)
      get project_explore_path(project)
      expect(response.body).to include("My view", "Team view")
      expect(response.body).not_to include("Their secret")
    end

    it "404s instead of failing when the view param is not a scalar" do
      view = create(:saved_view, project: project, user: owner)
      sign_in(owner)
      get "/projects/#{project.id}/explore?view[]=#{view.id}"
      expect(response).to have_http_status(:not_found)
      get "/projects/#{project.id}/explore?view[x]=#{view.id}"
      expect(response).to have_http_status(:not_found)
    end

    it "offers the share checkbox to members and up only" do
      sign_in(member("viewer"))
      get project_explore_path(project)
      expect(response.body).not_to include('name="saved_view[shared]"')
      sign_in(member("member"))
      get project_explore_path(project)
      expect(response.body).to include('name="saved_view[shared]"')
    end
  end

  it "turns the quarantined checkbox into is:quarantined and lists the status checkbox" do
    sign_in(owner)
    get project_explore_path(project, fields: "1", quarantined: "1", statuses: [ "quarantined" ])
    expect(response).to redirect_to(project_explore_path(project, level: "tests", q: "status:quarantined is:quarantined"))

    follow_redirect!
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css("#status_quarantined")["checked"]).to be_present
    expect(doc.at_css("#filter_quarantined")["checked"]).to be_present
  end
end
