require "rails_helper"

RSpec.describe "config/database.yml production" do
  def production(env = {})
    stub_const("ENV", ENV.to_h.merge(env))
    YAML.load(ERB.new(Rails.root.join("config/database.yml").read).result, aliases: true).fetch("production")
  end

  it "keeps every SQLite database under storage/, the volume Kamal mounts" do
    config = production("DB_ADAPTER" => nil)
    expect(config.dig("primary", "database")).to eq("storage/production.sqlite3")
    expect(config.dig("cache", "database")).to eq("storage/production_cache.sqlite3")
    expect(config.dig("queue", "database")).to eq("storage/production_queue.sqlite3")
    expect(config.dig("cable", "database")).to eq("storage/production_cable.sqlite3")
  end

  it "leaves the Postgres primary to DATABASE_URL" do
    config = production("DB_ADAPTER" => "postgresql")
    expect(config.dig("primary", "adapter")).to eq("postgresql")
    expect(config.dig("primary", "database")).to be_nil
    expect(config.dig("queue", "database")).to eq("storage/production_queue.sqlite3")
  end
end
