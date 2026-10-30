require "rails_helper"

# Every setting the app reads is in docs/install/configuration.md (spec 2026-10-29 §7.3).
RSpec.describe "docs/install/configuration.md" do
  internal = %w[CI TEST_ENV_NUMBER PIDFILE BUNDLE_GEMFILE FILE KAMAL_VERSION KAMAL_REGISTRY_IMAGE KAMAL_SERVER_IP
                KAMAL_REGISTRY_SERVER KAMAL_REGISTRY_USERNAME SECRET_KEY_BASE_DUMMY EMAIL ORG PROJECT PASSWORD NAME
                RAILS_ENV RACK_ENV]

  it "documents every environment variable the app reads" do
    doc = Rails.root.join("docs/install/configuration.md").read
    files = Dir[Rails.root.join("{app,config,lib}/**/*.{rb,yml,erb,rake}")]
    names = files.flat_map { |file| File.read(file).scan(/(?:ENV|env)(?:\.fetch\(|\[)\s*"([A-Z][A-Z0-9_]+)"/).flatten }
    names += StorageService::FALLBACKS.to_a.flatten + Hideout::Secrets::NAMES
    missing = (names.uniq - internal).reject { |name| doc.include?("`#{name}`") }
    expect(missing).to be_empty
  end
end
