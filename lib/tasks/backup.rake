namespace :backup do
  desc "Snapshot the primary database into BACKUP_DIR"
  task create: :environment do
    path = Backup.new.create
    puts path ? "Backup written: #{path}" : "Backup skipped: the primary database is not SQLite"
  end

  desc "Unpack and check a backup next to the live database (FILE=path); never replaces it"
  task restore: :environment do
    file = ENV["FILE"].presence || abort("Usage: bin/rails backup:restore FILE=storage/backups/raider-YYYYMMDD-HHMMSS.sqlite3.gz")
    restored = Backup.new.restore(file)
    live = restored.sub_ext("")
    puts <<~STEPS
      Restored and checked: #{restored}
      To switch to it:
        1. Stop the app.
        2. mv #{restored} #{live} && rm -f #{live}-wal #{live}-shm
        3. Start the app.
    STEPS
  end

  desc "Download a backup from the offsite bucket into BACKUP_DIR (FILE=raider-YYYYMMDD-HHMMSS.sqlite3.gz)"
  task fetch: :environment do
    abort("Offsite backups are not configured: set BACKUP_BUCKET") unless Backup::Offsite.enabled?
    name = ENV["FILE"].presence || abort("Usage: bin/rails backup:fetch FILE=raider-YYYYMMDD-HHMMSS.sqlite3.gz")
    path = Backup::Offsite.new.fetch(name, Backup.dir)
    puts "Fetched: #{path}"
    puts "Next: bin/rails backup:restore FILE=#{path}"
  end
end
