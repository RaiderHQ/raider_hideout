require "raider_reporter/rspec"

RaiderReporter.configure do |c|
  c.environment = { "app" => "raider_saas", "browser" => "chrome", "headless" => true }
end

RSpec.configure do |config|
  config.after(type: :system) do |example|
    next unless example.exception

    path = Rails.root.join("tmp/screenshots/raider-#{example.id.gsub(/\W/, '_')}.png").to_s
    FileUtils.mkdir_p(File.dirname(path))
    page.save_screenshot(path)
    RaiderReporter.attach("screenshot", path, type: :png)
  end
end
