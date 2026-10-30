require "rails_helper"

RSpec.describe Backup do
  let(:dir) { Pathname(Dir.mktmpdir("raider-backups")) }
  let(:backup) { described_class.new(dir: dir) }
  let(:now) { Time.utc(2026, 10, 20, 2, 30, 0) }

  after { FileUtils.rm_rf(dir) }

  describe "#create and #restore", sqlite_only: true do
    self.use_transactional_tests = false

    let!(:channel) { create(:notification_channel) }

    after do
      FileUtils.rm_f("#{described_class.new(dir: dir).send(:database_path)}.restored")
      [ NotificationChannel, Project, Membership, Organization, Session, User ].each(&:delete_all)
    end

    it "writes a compressed snapshot that restores with the same rows and still-decryptable secrets" do
      path = backup.create(now: now)

      expect(path.basename.to_s).to eq("raider-20261020-023000.sqlite3.gz")
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      expect(File.stat(dir).mode & 0o777).to eq(0o700)
      expect(dir.children.map { |p| p.basename.to_s }).to eq([ path.basename.to_s ]) # no temporary files left

      restored = backup.restore(path)
      db = SQLite3::Database.new(restored.to_s, readonly: true)
      expect(db.get_first_value("SELECT COUNT(*) FROM notification_channels")).to eq(NotificationChannel.count)
      ciphertext = db.get_first_value("SELECT webhook_url FROM notification_channels WHERE id = ?", channel.id)
      expect(NotificationChannel.type_for_attribute(:webhook_url).deserialize(ciphertext)).to eq(channel.webhook_url)
    ensure
      db&.close
    end
  end

  it "raises and keeps old backups when the snapshot fails its check", sqlite_only: true do
    old = dir.join("raider-20261019-023000.sqlite3.gz")
    File.write(old, "old")
    allow(backup).to receive(:check!).and_raise(Backup::Failed, "quick_check failed")

    expect { backup.create(now: now) }.to raise_error(Backup::Failed, "quick_check failed")
    expect(dir.children).to eq([ old ])
  end

  it "raises Backup::Failed for a missing file" do
    expect { backup.restore(dir.join("raider-20261019-023000.sqlite3.gz")) }
      .to raise_error(Backup::Failed, /could not be read/)
  end

  it "raises Backup::Failed for a file that is not a backup and leaves no restored file" do
    bogus = dir.join("raider-20261019-023000.sqlite3.gz")
    File.write(bogus, "not gzip")

    expect { backup.restore(bogus) }.to raise_error(Backup::Failed, /not a valid backup/)
    expect(File.exist?("#{backup.send(:database_path)}.restored")).to be(false)
  end

  it "skips with a log line when the database is not SQLite" do
    config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", { adapter: "postgresql" })
    logger = instance_double(Logger, info: nil)

    expect(described_class.new(dir: dir, db_config: config, logger: logger).create(now: now)).to be_nil
    expect(logger).to have_received(:info).with("[backup] skipped: adapter postgresql is not SQLite")
    expect(dir.children).to be_empty
  end

  it "raises and leaves everything alone when the database file is missing" do
    missing = dir.join("nope", "missing.sqlite3")
    config = ActiveRecord::DatabaseConfigurations::HashConfig.new("test", "primary", { adapter: "sqlite3", database: missing.to_s })
    old = dir.join("raider-20261019-023000.sqlite3.gz")
    File.write(old, "old")

    expect { described_class.new(dir: dir, db_config: config).create(now: now) }
      .to raise_error(Backup::Failed, "database not found: #{missing}")
    expect(File.exist?(missing)).to be(false)
    expect(dir.children).to eq([ old ])
  end

  describe "#rotate" do
    def stamp(time) = dir.join("raider-#{time.strftime('%Y%m%d-%H%M%S')}.sqlite3.gz")

    it "keeps the 7 newest and the newest of each of the 4 most recent ISO weeks, and nothing else matching" do
      days = (0..40).map { |n| Time.utc(2026, 10, 20, 2, 30) - n.days }
      days.each { |t| File.write(stamp(t), "x") }
      File.write(dir.join("notes.txt"), "keep me")

      backup.rotate

      kept = dir.children.map { |p| p.basename.to_s }.sort
      newest_seven = days.first(7).map { |t| stamp(t).basename.to_s }
      weekly = days.group_by { |t| [ t.to_date.cwyear, t.to_date.cweek ] }.values.first(4).map { |ts| stamp(ts.max).basename.to_s }
      expect(kept).to eq((newest_seven + weekly + [ "notes.txt" ]).uniq.sort)
    end
  end

  it "defaults the directory to storage/backups, overridable by BACKUP_DIR" do
    expect(described_class.dir).to eq(Rails.root.join("storage/backups"))
    stub_const("ENV", ENV.to_h.merge("BACKUP_DIR" => "/var/backups/raider"))
    expect(described_class.dir).to eq(Pathname("/var/backups/raider"))
  end

  describe ".keep" do
    it "keeps the 7 newest plus the newest of each of the 4 most recent weeks, newest first" do
      days = (1..40).map { |n| (Date.new(2026, 10, 20) - n).strftime("raider-%Y%m%d-023000.sqlite3.gz") }
      kept = Backup.keep(days.shuffle + [ "notes.txt" ])
      expect(kept.first(7)).to eq(days.first(7))
      expect(kept.size).to be <= 11
      expect(kept).not_to include("notes.txt")
      expect(kept).to eq(kept.sort.reverse)
    end
  end
end
