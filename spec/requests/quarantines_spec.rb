require "rails_helper"

RSpec.describe "Quarantines", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:org) { create(:organization) }
  let(:project) { create(:project, organization: org) }
  let(:member) { create(:user).tap { |u| create(:membership, organization: org, user: u, role: "member") } }
  let(:test_case) { create(:test_case, project: project, full_name: "Checkout pays") }
  let(:now) { Time.zone.parse("2026-10-24 12:00:00") }
  let(:test_page) { project_test_case_path(project, test_case, anchor: "quarantine") }

  around { |example| travel_to(now) { example.run } }

  before { sign_in(member) }

  def quarantine!(days: 14, reason: "Waits on mail", target: test_case)
    Quarantine.quarantine!(test_case: target, user: member, reason: reason, days: days)
  end

  def create_with(attrs)
    post project_test_case_quarantines_path(project, test_case), params: { quarantine: attrs }
  end

  describe "create" do
    it "quarantines the test and shows the banner" do
      create_with(reason: "Waits on mail", days: "7")

      expect(response).to redirect_to(test_page)
      expect(flash[:notice]).to eq("Quarantined until October 31, 2026.")
      q = test_case.quarantines.sole
      expect(q).to have_attributes(reason: "Waits on mail", expires_at: now + 7.days, created_by: member)
      expect(q.events.pluck(:action, :actor_id)).to eq([ [ "quarantined", member.id ] ])

      get project_test_case_path(project, test_case)
      banner = Nokogiri::HTML(response.body).at_css("[data-testid=quarantine-banner]").text.squish
      expect(banner).to eq("Quarantined until October 31, 2026 by #{member.email_address}: Waits on mail")
    end

    it "defaults to 14 days when no duration is sent" do
      create_with(reason: "Waits on mail")
      expect(test_case.quarantines.sole.expires_at).to eq(now + 14.days)
    end

    it "alerts with the expiry when the test is already quarantined" do
      quarantine!(days: 14)
      create_with(reason: "again", days: "7")
      expect(response).to redirect_to(test_page)
      expect(flash[:alert]).to eq("Already quarantined until November 7, 2026")
      expect(test_case.quarantines.count).to eq(1)
    end

    {
      { reason: "", days: "7" } => "Reason can't be blank",
      { reason: "x" * 501, days: "7" } => "Reason is too long (maximum is 500 characters)",
      { reason: "flaky", days: "45" } => "Duration must be 7, 14 or 30 days"
    }.each do |attrs, message|
      it "alerts #{message.inspect} and stores nothing" do
        create_with(attrs)
        expect(response).to redirect_to(test_page)
        expect(flash[:alert]).to eq(message)
        expect(Quarantine.count).to eq(0)
      end
    end

    it "returns 404 for another organization's test" do
      foreign = create(:test_case)
      post project_test_case_quarantines_path(foreign.project, foreign), params: { quarantine: { reason: "x", days: "7" } }
      expect(response).to have_http_status(:not_found)
      post project_test_case_quarantines_path(project, foreign), params: { quarantine: { reason: "x", days: "7" } }
      expect(response).to have_http_status(:not_found)
      expect(Quarantine.count).to eq(0)
    end
  end

  describe "update (extend)" do
    it "extends from now by the chosen days with an optional note" do
      q = quarantine!(days: 7)
      travel 2.days
      patch project_quarantine_path(project, q), params: { quarantine: { days: "30", note: "still flaky" } }

      expect(response).to redirect_to(test_page)
      expect(flash[:notice]).to eq("Quarantine extended until November 25, 2026.")
      expect(q.reload.expires_at).to eq(Time.current + 30.days)
      expect(q.events.order(:id).last).to have_attributes(action: "extended", note: "still flaky", actor: member)
    end

    it "says the quarantine is no longer active once it expired" do
      q = quarantine!(days: 7)
      travel 8.days
      patch project_quarantine_path(project, q), params: { quarantine: { days: "7" } }
      expect(flash[:notice]).to eq("This quarantine is no longer active")
      expect(q.events.count).to eq(1)
    end

    it "alerts an invalid duration" do
      q = quarantine!
      patch project_quarantine_path(project, q), params: { quarantine: { days: "2" } }
      expect(flash[:alert]).to eq("Duration must be 7, 14 or 30 days")
    end
  end

  describe "destroy (release)" do
    it "releases without deleting and records the note" do
      q = quarantine!
      delete project_quarantine_path(project, q), params: { quarantine: { note: "fixed" } }

      expect(response).to redirect_to(test_page)
      expect(flash[:notice]).to eq("Quarantine released.")
      expect(q.reload).to have_attributes(released_at: now, released_by: member)
      expect(q.events.order(:id).pluck(:action, :note)).to eq([ [ "quarantined", nil ], [ "released", "fixed" ] ])
    end

    it "says the quarantine is no longer active when it was already released" do
      q = quarantine!
      q.release!(user: member)
      delete project_quarantine_path(project, q)
      expect(flash[:notice]).to eq("This quarantine is no longer active")
      expect(q.events.count).to eq(2)
    end

    it "returns 404 for another organization's quarantine" do
      foreign = create(:quarantine)
      delete project_quarantine_path(project, foreign)
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.released_at).to be_nil
    end
  end

  describe "test page" do
    it "shows the quarantine form with 7, 14 and 30 days, 14 selected, when not quarantined" do
      get project_test_case_path(project, test_case)
      doc = Nokogiri::HTML(response.body)
      expect(doc.css("#quarantine_days option").map { |o| [ o["value"], o["selected"].present? ] })
        .to eq([ [ "7", false ], [ "14", true ], [ "30", false ] ])
      expect(doc.at_css("#quarantine_reason")["maxlength"]).to eq("500")
    end

    it "lists the test's quarantine history newest first" do
      q = quarantine!
      travel 1.hour
      q.extend_by!(user: member, days: 30, note: "still flaky")
      travel 1.hour
      q.release!(user: member)

      get project_test_case_path(project, test_case)
      actions = Nokogiri::HTML(response.body).css("[data-quarantine-event]").map { |row| row["data-quarantine-event"] }
      expect(actions).to eq(%w[released extended quarantined])
    end

    it "caps the test's quarantine history at the 50 newest events" do
      q = quarantine!
      50.times do |i|
        q.events.create!(action: "extended", actor: member, expires_at: q.expires_at, note: "n#{i}", created_at: now + (i + 1).minutes)
      end

      get project_test_case_path(project, test_case)
      rows = Nokogiri::HTML(response.body).css("[data-quarantine-event]")
      expect(rows.size).to eq(50)
      expect(rows.map { _1["data-quarantine-event"] }.uniq).to eq(%w[extended])
      expect(rows.first.text).to include("n49")
    end
  end

  describe "scalar quarantine param" do
    it "returns 400 instead of raising" do
      post project_test_case_quarantines_path(project, test_case), params: { quarantine: "foo" }
      expect(response).to have_http_status(:bad_request)
      expect(test_case.quarantines).to be_empty
    end

    it "returns 400 on release too" do
      q = quarantine!
      delete project_quarantine_path(project, q), params: { quarantine: "foo" }
      expect(response).to have_http_status(:bad_request)
      expect(q.reload.released_at).to be_nil
    end
  end

  describe "flaky list" do
    def flaky(name)
      create(:test_case, project: project, full_name: name).tap do |kase|
        create(:test_case_verdict, test_case: kase, branch: "main", flaky: true, flaky_reason: "flips", flip_rate: 0.4)
      end
    end

    it "offers Quarantine on unquarantined rows and a Quarantined badge on quarantined ones" do
      open = flaky("Open flaky")
      held = flaky("Held flaky")
      quarantine!(target: held)

      get project_flaky_tests_path(project)
      doc = Nokogiri::HTML(response.body)

      links = doc.css("a").select { |a| a.text.strip == "Quarantine" }.map { |a| a["href"] }
      expect(links).to eq([ project_test_case_path(project, open, branch: "main", anchor: "quarantine") ])
      expect(doc.css("[data-testid=quarantined-badge]").size).to eq(1)
    end
  end

  describe "quarantine page" do
    it "lists active quarantines by expiry and the 50 most recent events, and is linked from the project page" do
      later = quarantine!(days: 30, target: create(:test_case, project: project, full_name: "Later"))
      sooner = quarantine!(days: 7, target: create(:test_case, project: project, full_name: "Sooner"))
      quarantine!(target: create(:test_case, project: project, full_name: "Gone")).release!(user: member)
      49.times { |i| later.events.create!(action: "extended", actor: member, expires_at: later.expires_at, note: "n#{i}") }

      get project_quarantined_tests_path(project)
      doc = Nokogiri::HTML(response.body)

      expect(doc.css("[data-quarantine-row]").map { |row| row["data-quarantine-row"].to_i }).to eq([ sooner.id, later.id ])
      expect(doc.css("[data-quarantine-event]").size).to eq(50)

      get project_path(project)
      expect(Nokogiri::HTML(response.body).css("a").map { |a| a["href"] }).to include(project_quarantined_tests_path(project))
    end
  end
end
