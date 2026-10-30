require "rails_helper"
require "rake"

RSpec.describe "backup rake tasks" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "backup:fetch" } }

  describe "backup:fetch" do
    it "downloads the named backup into BACKUP_DIR and prints the restore command" do
      dir = Pathname(Dir.mktmpdir)
      offsite = instance_double(Backup::Offsite)
      allow(Backup::Offsite).to receive_messages(enabled?: true, new: offsite)
      allow(Backup).to receive(:dir).and_return(dir)
      allow(offsite).to receive(:fetch).with("raider-20261020-023000.sqlite3.gz", dir)
                                       .and_return(dir.join("raider-20261020-023000.sqlite3.gz"))
      stub_const("ENV", ENV.to_h.merge("FILE" => "raider-20261020-023000.sqlite3.gz"))
      expect { Rake::Task["backup:fetch"].execute }
        .to output(/Fetched: .*raider-20261020-023000\.sqlite3\.gz\nNext: bin\/rails backup:restore FILE=/).to_stdout
    end

    it "aborts when offsite backups are not configured" do
      allow(Backup::Offsite).to receive(:enabled?).and_return(false)
      expect { Rake::Task["backup:fetch"].execute }.to raise_error(SystemExit).and output(/set BACKUP_BUCKET/).to_stderr
    end
  end
end
