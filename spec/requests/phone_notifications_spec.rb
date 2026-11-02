require "rails_helper"

RSpec.describe "Phone notifications", type: :request do
  let(:user) { create(:user) }
  let!(:mine) { create(:project, owner: user, name: "Checkout") }
  let!(:other_org_project) { create(:project, name: "Secret") }

  def page_html = Nokogiri::HTML(response.body)

  it "redirects a signed-out visitor to sign in" do
    get phone_notifications_path
    expect(response).to redirect_to(new_session_path)
  end

  context "signed in" do
    before { sign_in(user) }

    it "shows the configuration error instead of the button when only one VAPID variable is set" do
      ENV["HIDEOUT_VAPID_PUBLIC_KEY"] = "abc"
      get phone_notifications_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("HIDEOUT_VAPID_PRIVATE_KEY is not set")
      expect(response.body).not_to include("Turn on notifications")
    ensure
      ENV.delete("HIDEOUT_VAPID_PUBLIC_KEY")
    end

    it "shows the note, the button, this user's devices, three switches and the visible projects" do
      user.push_subscriptions.create!(endpoint: fcm_endpoint, p256dh: valid_p256dh, auth: valid_auth, device_label: "iPhone")
      create(:user).push_subscriptions.create!(endpoint: fcm_endpoint("zzz"), p256dh: valid_p256dh, auth: valid_auth, device_label: "OtherPersonPhone")

      get phone_notifications_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Phone notifications",
        "On iPhone and iPad, add Hideout to your Home Screen first (Share → Add to Home Screen). iOS 17.2 or later.",
        "Turn on notifications", "Checkout")
      expect(response.body).not_to include("Secret", "OtherPersonPhone")
      expect(page_html.css("li button").map(&:text)).to eq([ "Remove" ])
      expect(response.body).to include(VapidKey.current.public_key)
      names = page_html.css("input[type=checkbox]").map { _1["name"] }
      expect(names).to contain_exactly("push_preference[default_branch_failures]", "push_preference[new_flaky]",
                                       "push_preference[gate_failures]", "project_ids[]")
      expect(response.body).not_to include("rerun_results")
      expect(page_html.at_css("#project_ids_#{mine.id}")["checked"]).to be_present
    end

    it "links to the page from the account menu" do
      get projects_path
      link = page_html.at_css("#account-menu a[href='#{phone_notifications_path}']")
      expect(link.text).to eq("Phone notifications")
      expect(link["class"]).to include("min-h-11")
    end

    it "saves the switches and mutes unchecked projects" do
      second = create(:project, owner: user, name: "Search")
      patch phone_notifications_path, params: { push_preference: { default_branch_failures: "0", new_flaky: "1", gate_failures: "1" },
                                                shown_project_ids: [ mine.id.to_s, second.id.to_s ], project_ids: [ mine.id.to_s ] }
      expect(response).to redirect_to(phone_notifications_path)
      expect(user.push_preference!).to have_attributes(default_branch_failures: false, new_flaky: true, gate_failures: true, rerun_results: true)
      expect(user.push_muted_projects.pluck(:project_id)).to eq([ second.id ])

      get phone_notifications_path
      expect(page_html.at_css("#project_ids_#{second.id}")["checked"]).to be_nil
      expect(page_html.at_css("#project_ids_#{mine.id}")["checked"]).to be_present
    end

    it "ignores project ids outside the user's projects and never mutes them" do
      patch phone_notifications_path, params: { shown_project_ids: [ mine.id.to_s, other_org_project.id.to_s, "junk" ],
                                                project_ids: [ mine.id.to_s, other_org_project.id.to_s, "junk" ] }
      expect(PushMutedProject.count).to eq(0)
      patch phone_notifications_path, params: { shown_project_ids: [ mine.id.to_s, other_org_project.id.to_s ],
                                                project_ids: [ other_org_project.id.to_s ] }
      expect(user.push_muted_projects.pluck(:project_id)).to eq([ mine.id ])
    end

    it "leaves a project created after the page was rendered unmuted" do
      get phone_notifications_path
      newer = create(:project, owner: user, name: "Newer")
      patch phone_notifications_path, params: { shown_project_ids: [ mine.id.to_s ], project_ids: [] }
      expect(user.push_muted_projects.pluck(:project_id)).to eq([ mine.id ])
      expect(newer).not_to be_nil
    end

    it "leaves existing mutes untouched when no project params are posted" do
      create(:project, owner: user, name: "Unmuted")
      user.push_muted_projects.create!(project: mine)
      patch phone_notifications_path, params: { push_preference: { new_flaky: "1" } }
      expect(response).to redirect_to(phone_notifications_path)
      expect(user.push_muted_projects.pluck(:project_id)).to eq([ mine.id ])
      expect(user.push_preference!.new_flaky).to be(true)
    end

    it "ignores a push_preference that is not an object" do
      patch phone_notifications_path, params: { push_preference: "boom" }
      expect(response).to redirect_to(phone_notifications_path)
    end

    it "does not touch another user's preferences or mutes" do
      other = create(:user)
      other.push_preference!
      create(:membership, user: other, organization: mine.organization)
      other.push_muted_projects.create!(project: mine)
      patch phone_notifications_path, params: { push_preference: { new_flaky: "1" }, shown_project_ids: [ mine.id.to_s ], project_ids: [ mine.id.to_s ] }
      expect(other.push_preference!.new_flaky).to be(false)
      expect(other.push_muted_projects.count).to eq(1)
    end
  end
end
