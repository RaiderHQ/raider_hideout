require "rails_helper"

RSpec.describe "Installable web app", type: :request do
  describe "manifest" do
    it "is served signed out with the app identity" do
      get pwa_manifest_path

      expect(response).to have_http_status(:ok)
      manifest = JSON.parse(response.body)
      expect(manifest).to include(
        "name" => "Raider Hideout", "short_name" => "Hideout", "start_url" => "/projects",
        "scope" => "/", "display" => "standalone", "theme_color" => "#C14420", "background_color" => "#FFFFFF"
      )
    end

    it "lists 192 and 512 PNG icons plus a maskable 512" do
      get pwa_manifest_path

      icons = JSON.parse(response.body).fetch("icons").map { |i| i.values_at("src", "sizes", "type", "purpose") }
      expect(icons).to contain_exactly(
        [ "/icon-192.png", "192x192", "image/png", nil ],
        [ "/icon-512.png", "512x512", "image/png", nil ],
        [ "/icon-512.png", "512x512", "image/png", "maskable" ]
      )
    end

    it "points at icon files that exist at the sizes declared" do
      { "icon-192.png" => 192, "icon-512.png" => 512 }.each do |file, size|
        header = Rails.public_path.join(file).binread(24)
        expect(header.byteslice(0, 8)).to eq("\x89PNG\r\n\x1A\n".b)
        expect(header.byteslice(16, 8).unpack("N2")).to eq([ size, size ])
      end
    end
  end

  describe "service worker" do
    it "is JavaScript, signed out, and never cached by the browser" do
      get pwa_service_worker_path

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/javascript")
      expect(response.headers["Cache-Control"]).to include("no-cache")
      expect(response.headers).not_to have_key("Service-Worker-Allowed")
    end

    describe "source" do
      let(:source) { get(pwa_service_worker_path) && response.body }

      it "caches only the offline page and intercepts navigations only" do
        expect(source).to include('const OFFLINE_CACHE = "hideout-offline-v1"', 'const OFFLINE_URL = "/offline"')
        expect(source).to include("caches.open(OFFLINE_CACHE).then((cache) => cache.add(OFFLINE_URL))")
        expect(source).to include("cached || Response.error()")
        expect(source).to include('request.mode !== "navigate"').or include('request.mode === "navigate"')
        expect(source.scan("respondWith").size).to eq(1)
        expect(source).not_to match(/cache\.put|addAll/)
      end

      it "opens only same-origin paths from a notification click" do
        expect(source).to include("new URL(path, self.location.origin)")
        expect(source).to include("url.origin === self.location.origin")
        expect(source).to include('"/projects"')
      end

      it "falls back to a new window when navigating an uncontrolled tab fails" do
        expect(source).to include(".then((navigated) => navigated && navigated.focus())")
        expect(source).to include(".catch(() => self.clients.openWindow(url.href))")
      end

      it "always shows a notification for a push, even without a usable payload" do
        expect(source).to include("self.registration.showNotification(title, {")
        expect(source).to include("} catch (_error) {\n    payload = {}")
        expect(source).to include('payload.title : "Raider Hideout"')
        expect(source).to include("const path = typeof payload.path === \"string\" ? payload.path : FALLBACK_PATH")
      end
    end
  end

  describe "offline page" do
    it "is served signed out without the navigation" do
      get offline_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You're offline", "Raider Hideout needs a connection to show results.")
      expect(response.body).not_to include("<nav")
    end
  end

  it "serves the offline page before any user exists instead of redirecting to setup" do
    User.delete_all
    Rails.configuration.x.first_run_redirect = true
    FirstRun.reset!

    get offline_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Raider Hideout needs a connection to show results.")
  ensure
    Rails.configuration.x.first_run_redirect = false
    FirstRun.reset!
  end

  it "links the manifest and touch icon from the layout" do
    get new_session_path

    expect(response.body).to include('rel="manifest" href="/manifest.json"')
    expect(response.body).to include('rel="apple-touch-icon" href="/icon-192.png"')
  end
end
