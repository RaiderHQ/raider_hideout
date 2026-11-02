require "rails_helper"

RSpec.describe "Installable web app", type: :system do
  let(:user) { create(:user) }

  before do
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  it "registers the service worker and caches the offline page" do
    visit projects_path
    expect(page).to have_css("link[rel=manifest]", visible: :all)

    script_url = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      navigator.serviceWorker.ready.then((registration) => done(registration.active.scriptURL));
    JS
    expect(script_url).to end_with("/service-worker.js")

    cached = nil
    Timeout.timeout(5) do
      loop do
        cached = page.evaluate_async_script(<<~JS)
          const done = arguments[arguments.length - 1];
          caches.open("hideout-offline-v1").then((cache) => cache.keys()).then((keys) => done(keys.map((r) => new URL(r.url).pathname)));
        JS
        break if cached.any?
        sleep 0.1
      end
    end
    expect(cached).to eq([ "/offline" ])
  end

  it "shows the offline page at phone widths" do
    [ 360, 430 ].each do |width|
      at_phone_width(width) do
        visit offline_path
        expect(page).to have_content("You're offline")
        expect_no_horizontal_scroll
      end
    end
  end
end
