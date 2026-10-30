source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3", ">= 2.1"
# Optional: DB_ADAPTER=postgresql switches the primary database (spec 2026-10-20 §4.3).
group :postgres do
  gem "pg", "~> 1.5"
end
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.2"

# Attachments in Cloudflare R2 through Active Storage's S3 service (spec 2026-10-21 §4.2)
gem "aws-sdk-s3", require: false

# Error tracking, on only when SENTRY_DSN is set (spec 2026-10-21 §4.4)
gem "sentry-ruby"
gem "sentry-rails"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Ruby and RubyGems versions with known vulnerabilities [https://github.com/civisanalytics/ruby_audit]
  gem "ruby_audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Preview emails in the browser at /letter_opener
  gem "letter_opener_web", "~> 3.0"

  # Deploys to one server behind Cloudflare (spec 2026-10-21 §4.1)
  gem "kamal", require: false
end

gem "pagy", "~> 43.8"
gem "chartkick", "~> 5.1"
# Analytics CSV export; a bundled gem since Ruby 3.4, so it must be listed (spec 2026-10-28 §4.6).
gem "csv", "~> 3.3"
gem "mcp", "~> 1.8.1"

group :development, :test do
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails", "~> 6.4"
end

group :test do
  gem "webmock"
  gem "capybara", "~> 3.40"
  gem "selenium-webdriver", "~> 4.47"
  gem "raider_reporter", "~> 0.7"
  gem "json_schemer", "~> 2.5"
end
