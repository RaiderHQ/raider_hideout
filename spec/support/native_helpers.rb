module NativeHelpers
  IOS_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 " \
              "Hotwire Native iOS; Turbo Native iOS; bridge-components: [];".freeze
  ANDROID_AGENT = "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile " \
                  "Safari/537.36 Hotwire Native Android; Turbo Native Android; bridge-components: [];".freeze
  BROWSER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15".freeze

  def ios_agent(version = "18_0") = IOS_AGENT.sub("18_0", version)

  # Request specs: headers for a request from the Raider app on iOS.
  def as_hotwire_native_ios(version = "18_0") = { "HTTP_USER_AGENT" => ios_agent(version) }
end

# A headless Chrome that sends the Raider app's iOS user agent, for system specs of native mode.
Capybara.register_driver :hotwire_native_ios do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--window-size=390,844")
  options.add_argument("--user-agent=#{NativeHelpers::IOS_AGENT}")
  options.add_preference("credentials_enable_service", false)
  options.add_preference("profile.password_manager_enabled", false)
  options.add_preference("profile.password_manager_leak_detection", false)
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

RSpec.configure { |c| c.include NativeHelpers }
