require "rails_helper"

RSpec.describe "Gate rules", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:org) { create(:organization) }
  let(:project) { create(:project, organization: org) }
  let(:users) do
    Membership::ROLES.index_with do |role|
      create(:user).tap { |u| create(:membership, organization: org, user: u, role: role) }
    end
  end
  let(:valid) { { gate_rule: { min_pass_rate: "98", no_new_failures: "1", no_new_flaky: "0" } } }

  def act_as(role) = sign_in(users.fetch(role))

  def html = Nokogiri::HTML(response.body)

  Membership::ROLES.each do |role|
    it "lets a #{role} view the gate page" do
      act_as(role)
      get project_gate_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Quality gate", "Minimum pass rate (%)",
                                       "passed ÷ (passed + failed); quarantined tests are ignored",
                                       "No new failures vs the default branch", "No new flaky tests")
    end
  end

  %w[viewer member].each do |role|
    it "shows a #{role} the form disabled and forbids saving" do
      act_as(role)
      get project_gate_path(project)
      expect(response.body).to include("Only admins can change gate rules")
      expect(html.at_css("input[name='gate_rule[min_pass_rate]']")["disabled"]).to eq("disabled")
      expect(html.at_css("input[type=checkbox][name='gate_rule[no_new_failures]']")["disabled"]).to eq("disabled")
      expect(html.at_css("input[type=submit][value='Save gate rules']")["disabled"]).to eq("disabled")

      patch project_gate_path(project), params: valid
      expect(response).to have_http_status(:forbidden)
      expect(GateRule.count).to eq(0)
    end
  end

  %w[admin owner].each do |role|
    it "lets an #{role} save the rules and shows who changed them last" do
      travel_to Time.zone.parse("2026-10-24 12:00:00") do
        act_as(role)
        get project_gate_path(project)
        expect(response.body).not_to include("Only admins can change gate rules")

        patch project_gate_path(project), params: valid

        expect(response).to redirect_to(project_gate_path(project))
        expect(flash[:notice]).to eq("Gate rules saved. They apply to builds evaluated from now on.")
        expect(GateRule.find_by(project: project))
          .to have_attributes(min_pass_rate: 98, no_new_failures: true, no_new_flaky: false, updated_by: users.fetch(role))
        follow_redirect!
        expect(response.body).to include("Last changed October 24, 2026 by #{users.fetch(role).email_address}")
      end
    end
  end

  it "keeps one row per project and treats a blank minimum as off" do
    act_as("admin")
    patch project_gate_path(project), params: valid
    patch project_gate_path(project), params: { gate_rule: { min_pass_rate: "", no_new_failures: "0", no_new_flaky: "1" } }
    expect(GateRule.where(project: project).count).to eq(1)
    expect(GateRule.find_by(project: project)).to have_attributes(min_pass_rate: nil, no_new_failures: false, no_new_flaky: true)
  end

  it "survives two first saves racing on the unique index" do
    act_as("admin")
    raced = false
    allow_any_instance_of(GateRule).to receive(:save).and_wrap_original do |original, *args|
      next original.call(*args) if raced

      raced = true
      GateRule.create!(project: project, min_pass_rate: 50)
      raise ActiveRecord::RecordNotUnique
    end
    patch project_gate_path(project), params: valid
    expect(response).to redirect_to(project_gate_path(project))
    expect(GateRule.where(project: project).count).to eq(1)
    expect(GateRule.find_by(project: project)).to have_attributes(min_pass_rate: 98, no_new_failures: true, updated_by: users.fetch("admin"))
  end

  it "re-renders invalid input with the error and 422" do
    act_as("admin")
    { "0" => "must be in 1..100", "101" => "must be in 1..100", "abc" => "is not a number" }.each do |value, message|
      patch project_gate_path(project), params: { gate_rule: { min_pass_rate: value, no_new_failures: "0", no_new_flaky: "0" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(message)
    end
    expect(GateRule.count).to eq(0)
  end

  it "keeps the previous \"Last changed … by …\" on a failed update" do
    owner = users.fetch("owner")
    travel_to Time.zone.parse("2026-10-20 09:00:00") do
      GateRule.create!(project: project, min_pass_rate: 90, updated_by: owner)
    end
    act_as("admin")

    patch project_gate_path(project), params: { gate_rule: { min_pass_rate: "0", no_new_failures: "1", no_new_flaky: "0" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(html.at_css("[data-testid=gate-last-changed]").text.squish)
      .to eq("Last changed October 20, 2026 by #{owner.email_address}")
    expect(GateRule.find_by(project: project)).to have_attributes(min_pass_rate: 90, updated_by: owner)
  end

  it "returns 404 for a project in another organization" do
    sign_in(create(:user))
    get project_gate_path(project)
    expect(response).to have_http_status(:not_found)
    patch project_gate_path(project), params: valid
    expect(response).to have_http_status(:not_found)
    expect(GateRule.count).to eq(0)
  end

  it "puts a Gate button right after Notifications on the project page" do
    act_as("viewer")
    get project_path(project)
    gate = html.at_css("a[href='#{project_notification_channels_path(project)}'] + a")
    expect(gate.text).to eq("Gate")
    expect(gate["href"]).to eq(project_gate_path(project))
  end
end
