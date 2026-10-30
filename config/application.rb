require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Instance settings and secrets load before the environment files read them
# (spec 2026-10-29 §5.1).
require_relative "../lib/hideout/settings"
require_relative "../lib/hideout/secrets"
require_relative "../lib/hideout/setup_code"
Hideout::Secrets.load!(root: File.expand_path("..", __dir__), rails_env: Rails.env)

module Hideout
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks hideout])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Attachments are served by AttachmentsController, only to project members.
    config.active_storage.draw_routes = false
    # Rails only serves inline what is on this list; add the videos we embed.
    config.active_storage.content_types_allowed_inline += %w[video/mp4 video/webm]

    # While no user exists, HTML pages send visitors to /setup (spec 2026-10-29 §5.3).
    config.x.first_run_redirect = true
  end
end
