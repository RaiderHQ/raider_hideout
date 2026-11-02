require "rails_helper"

RSpec.describe "Phone notifications", type: :system do
  let(:user) { create(:user) }
  let!(:project) { create(:project, owner: user, name: "Checkout") }
  let(:cdp) { page.driver.browser }

  # Headless Chrome cannot reach a real push service, so only the browser's push service is
  # faked: permission resolves "granted" and PushManager.subscribe returns an FCM endpoint
  # with valid fake keys. The button, the POST, CSRF, controller and page are real.
  # Test env turns forgery protection off; switch it on so the fetch's X-CSRF-Token is checked.
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  def fake_push_service(permission: "granted")
    source = <<~JS
      (() => {
        Object.defineProperty(Notification, "requestPermission", { value: () => Promise.resolve(#{permission.to_json}), configurable: true });
        const bytes = (n, first) => { const a = new Uint8Array(n).map((_, i) => i + 1); if (first !== undefined) a[0] = first; return a; };
        const b64url = (a) => btoa(String.fromCharCode(...a)).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/, "");
        PushManager.prototype.subscribe = function (options) {
          window.__applicationServerKey = Array.from(new Uint8Array(options.applicationServerKey));
          window.__userVisibleOnly = options.userVisibleOnly;
          return Promise.resolve({ toJSON: () => ({
            endpoint: "https://fcm.googleapis.com/fcm/send/system-spec-device",
            expirationTime: null,
            keys: { p256dh: b64url(bytes(65, 4)), auth: b64url(bytes(16)) }
          }) });
        };
      })();
    JS
    cdp.execute_cdp("Page.addScriptToEvaluateOnNewDocument", source: source)
  end

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  def open_page_from_menu
    find("#account-menu summary").click
    within("#account-menu") { click_on "Phone notifications" }
    expect(page).to have_css("h1", text: "Phone notifications")
  end

  it "turns notifications on, saves a project switch, and removes the device at phone width" do
    fake_push_service
    sign_in_as(user)
    cdp.execute_cdp("Network.setUserAgentOverride",
                    userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1")

    at_phone_width(360) do
      visit projects_path
      open_page_from_menu
      expect(page).to have_content("On iPhone and iPad, add Hideout to your Home Screen first")
      expect_no_horizontal_scroll
      expect_tap_targets("main a, main button, main label, main input[type=submit]")

      click_on "Turn on notifications"
      expect(page).to have_css("li", text: "iPhone")
      expect(PushSubscription.count).to eq(1)
      expect(PushSubscription.sole).to have_attributes(user_id: user.id, device_label: "iPhone",
                                                       endpoint: "https://fcm.googleapis.com/fcm/send/system-spec-device")

      sent = page.evaluate_script("window.__applicationServerKey")
      expect(sent.pack("C*")).to eq(Base64.urlsafe_decode64(VapidKey.current.public_key))
      expect(page.evaluate_script("window.__userVisibleOnly")).to be(true)
      expect_no_horizontal_scroll

      uncheck "Checkout"
      click_on "Save"
      expect(page).to have_content("Phone notification settings saved.")
      expect(user.push_muted_projects.pluck(:project_id)).to eq([ project.id ])
      expect(page).to have_unchecked_field("Checkout")

      accept_confirm { click_on "Remove" }
      expect(page).to have_content("Device removed.")
      expect(page).to have_content("No devices yet.")
      expect(PushSubscription.count).to eq(0)
    end
  end

  it "says so when notifications are blocked and stores nothing" do
    fake_push_service(permission: "denied")
    sign_in_as(user)
    visit phone_notifications_path
    click_on "Turn on notifications"
    expect(page).to have_content("Notifications are blocked for this site in your browser settings.")
    expect(PushSubscription.count).to eq(0)
  end
end
