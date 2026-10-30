require "rails_helper"

RSpec.describe BackupJob do
  let(:path) do
    Pathname(Dir.mktmpdir).join("raider-20261020-023000.sqlite3.gz").tap { |p| File.write(p, "x" * 2048) }
  end
  let(:offsite) { instance_double(Backup::Offsite, upload: nil, rotate: nil) }

  before { allow(Rails.logger).to receive(:info) }

  it "creates a backup and logs its path and size" do
    allow(Backup).to receive(:new).and_return(instance_double(Backup, create: path))
    allow(Backup::Offsite).to receive(:enabled?).and_return(false)
    described_class.perform_now
    expect(Rails.logger).to have_received(:info).with("[backup] wrote #{path} (2 KB)")
  end

  it "logs nothing more and copies nothing when the backup was skipped" do
    allow(Backup).to receive(:new).and_return(instance_double(Backup, create: nil))
    allow(Backup::Offsite).to receive(:new)
    described_class.perform_now
    expect(Rails.logger).not_to have_received(:info).with(/wrote/)
    expect(Backup::Offsite).not_to have_received(:new)
  end

  it "copies the backup offsite and rotates the bucket when offsite is on" do
    allow(Backup).to receive(:new).and_return(instance_double(Backup, create: path))
    allow(Backup::Offsite).to receive_messages(enabled?: true, new: offsite)
    described_class.perform_now
    expect(offsite).to have_received(:upload).with(path).ordered
    expect(offsite).to have_received(:rotate).ordered
    expect(Rails.logger).to have_received(:info).with("[backup] copied raider-20261020-023000.sqlite3.gz offsite")
  end

  it "does not touch offsite storage when offsite is off" do
    allow(Backup).to receive(:new).and_return(instance_double(Backup, create: path))
    allow(Backup::Offsite).to receive(:enabled?).and_return(false)
    allow(Backup::Offsite).to receive(:new)
    described_class.perform_now
    expect(Backup::Offsite).not_to have_received(:new)
  end

  it "fails the job when the upload fails, keeping the local backup" do
    allow(Backup).to receive(:new).and_return(instance_double(Backup, create: path))
    allow(Backup::Offsite).to receive_messages(enabled?: true, new: offsite)
    allow(offsite).to receive(:upload).and_raise(Backup::Failed, "offsite upload: AccessDenied")
    expect { described_class.perform_now }.to raise_error(Backup::Failed, "offsite upload: AccessDenied")
    expect(path).to exist
  end

  it "is scheduled at 2:30am in production" do
    production = YAML.load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true).fetch("production")
    expect(production.fetch("backup")).to include("class" => "BackupJob", "schedule" => "at 2:30am every day")
  end

  it "checks in with Sentry's cron monitor so a backup that never runs alerts too" do
    expect(described_class.ancestors).to include(Sentry::Cron::MonitorCheckIns)
    expect(described_class.sentry_monitor_slug).to eq("backup-job")
    expect(described_class.sentry_monitor_config.schedule.value).to eq("30 2 * * *")
    expect(described_class.sentry_monitor_config.timezone).to eq("UTC")
  end
end
