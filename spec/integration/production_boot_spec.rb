require "rails_helper"
require "open3"

# Boots the real production environment in a subprocess (spec 2026-10-29 §5.1, §7.1).
# The script's own output is the last lines of stdout; the production logger writes above it.
RSpec.describe "Production boot" do
  let(:dir) { Pathname(Dir.mktmpdir) }
  let(:secrets) { dir.join("secrets.yml") }

  after { FileUtils.remove_entry(dir) }

  def boot(script, env = {})
    clean = (Hideout::Secrets::NAMES + %w[SECRET_KEY_BASE_DUMMY SMTP_ADDRESS HIDEOUT_FORCE_SSL HIDEOUT_ASSUME_SSL ALLOWED_HOSTS]).index_with { nil }
    base = clean.merge("RAILS_ENV" => "production", "APP_HOST" => "localhost:3010",
                       "HIDEOUT_SECRETS_FILE" => secrets.to_s,
                       "DATABASE_URL" => "sqlite3:#{dir.join('production.sqlite3')}")
    out, err, status = Open3.capture3(base.merge(env), "bin/rails", "runner", script, chdir: Rails.root.to_s)
    raise "boot failed: #{err}" unless status.success?

    [ out.lines.map(&:chomp), err ]
  end

  it "generates secrets on the first boot and reuses them on the next" do
    out, err = boot("puts Rails.application.secret_key_base, ActiveRecord::Encryption.config.primary_key")
    stored = YAML.safe_load(secrets.read)
    expect(out.last(2)).to eq([ stored["SECRET_KEY_BASE"], stored["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ])
    expect(err).to include("[hideout] generated secrets in #{secrets}")
    expect(File.stat(secrets).mode & 0o777).to eq(0o600)

    again, err_again = boot("puts Rails.application.secret_key_base")
    expect(again.last).to eq(stored["SECRET_KEY_BASE"])
    expect(err_again).not_to include("generated secrets")
  end

  def ssl_flags(env = {})
    boot("puts Rails.application.config.force_ssl, Rails.application.config.assume_ssl", env)
  end

  it "forces HTTPS but does not assume it by default, so plain HTTP is redirected" do
    expect(ssl_flags.first.last(2)).to eq(%w[true false])
  end

  it "assumes HTTPS only for a declared header-less proxy" do
    expect(ssl_flags("HIDEOUT_ASSUME_SSL" => "true").first.last(2)).to eq(%w[true true])
  end

  it "turns HTTPS off only when asked, with a warning" do
    out, err = ssl_flags("HIDEOUT_FORCE_SSL" => "false")
    expect(out.last(2)).to eq(%w[false false])
    expect(err).to include("[hideout] HTTPS is off")
  end

  it "accepts requests for an APP_HOST that carries a port" do
    out, = boot("puts Rails.application.config.hosts.inspect, Rails.application.routes.default_url_options[:host]")
    hosts, url_host = out.last(2)
    expect(hosts).to include('"localhost"')
    expect(url_host).to eq("localhost:3010")
  end

  it "marks static assets nosniff and far-future cacheable" do
    out, = boot("puts Rails.application.config.public_file_server.headers.inspect")
    expect(out.last).to include('"x-content-type-options" => "nosniff"', "cache-control", %("permissions-policy" => #{Hideout::PERMISSIONS_POLICY.inspect}))
  end
end
