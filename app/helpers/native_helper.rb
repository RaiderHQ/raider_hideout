# The Raider app (Hotwire Native) identifies itself in the user agent. Native mode changes
# rendering only: no controller logic or authorisation differs between the browser and the app.
module NativeHelper
  # nil for a legacy "Turbo Native" agent that names no platform: native mode still hides the
  # web nav (hotwire_native_app?), only the platform CSS hook is absent.
  def native_platform
    agent = request.user_agent.to_s
    if agent.include?("Hotwire Native iOS") || agent.include?("Turbo Native iOS") then "ios"
    elsif agent.include?("Hotwire Native Android") || agent.include?("Turbo Native Android") then "android"
    end
  end

  # Browsers keep their titles exactly; the app shows the short native title when a page sets one.
  def page_title
    browser_title = content_for(:title) || "Raider Hideout"
    hotwire_native_app? ? (content_for(:native_title) || browser_title) : browser_title
  end
end
