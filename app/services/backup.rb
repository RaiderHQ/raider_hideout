require "zlib"

# Nightly snapshot of the primary SQLite database (spec 2026-10-20 §4.2). Uses its
# own SQLite connection so VACUUM INTO never runs inside an Active Record transaction.
class Backup
  class Failed < StandardError; end

  PATTERN = /\Araider-(\d{8}-\d{6})\.sqlite3\.gz\z/
  DAILY = 7
  WEEKLY = 4

  def self.dir
    Pathname(ENV.fetch("BACKUP_DIR", Rails.root.join("storage/backups").to_s))
  end

  # The keep rule, shared by local and offsite rotation: the DAILY newest, plus
  # the newest file of each of the WEEKLY most recent ISO weeks. Newest first.
  def self.keep(names)
    sorted = names.grep(PATTERN).sort.reverse
    weekly = sorted.group_by { |name| week_of(name) }.values.first(WEEKLY).map(&:first)
    (sorted.first(DAILY) + weekly).uniq.sort.reverse
  end

  def self.week_of(name)
    date = Date.strptime(PATTERN.match(name)[1][0, 8], "%Y%m%d")
    [ date.cwyear, date.cweek ]
  end

  def initialize(dir: self.class.dir, db_config: ActiveRecord::Base.connection_db_config, logger: Rails.logger)
    @dir = Pathname(dir)
    @db_config = db_config
    @logger = logger
  end

  def create(now: Time.current)
    unless @db_config.adapter.to_s.start_with?("sqlite")
      @logger.info("[backup] skipped: adapter #{@db_config.adapter} is not SQLite")
      return
    end

    raise Failed, "database not found: #{database_path}" unless database_path.file?

    FileUtils.mkdir_p(@dir)
    File.chmod(0o700, @dir)
    stamp = now.utc.strftime("%Y%m%d-%H%M%S")
    raw = @dir.join(".raider-#{stamp}.sqlite3.tmp")
    packed = @dir.join(".raider-#{stamp}.sqlite3.gz.tmp")
    final = @dir.join("raider-#{stamp}.sqlite3.gz")

    snapshot(raw)
    check!(raw)
    Zlib::GzipWriter.open(packed.to_s) { |gz| File.open(raw, "rb") { |file| IO.copy_stream(file, gz) } }
    File.chmod(0o600, packed)
    File.rename(packed, final)
    rotate
    final
  ensure
    [ raw, packed ].compact.each { |path| FileUtils.rm_f(path) }
  end

  def rotate
    files = @dir.children.select { |path| path.file? && PATTERN.match?(path.basename.to_s) }
    keep = self.class.keep(files.map { |path| path.basename.to_s })
    files.reject { |path| keep.include?(path.basename.to_s) }.each { |path| FileUtils.rm_f(path) }
  end

  def restore(file)
    target = Pathname("#{database_path}.restored")
    Zlib::GzipReader.open(file.to_s) { |gz| File.open(target, "wb", 0o600) { |out| IO.copy_stream(gz, out) } }
    check!(target)
    target
  rescue SystemCallError => e
    FileUtils.rm_f(target) if target
    raise Failed, "#{Pathname(file).basename} could not be read: #{e.message}"
  rescue Zlib::Error, SQLite3::Exception, Failed => e
    FileUtils.rm_f(target) if target
    raise Failed, "#{Pathname(file).basename} is not a valid backup: #{e.message}"
  end

  private

  def database_path
    Pathname(@db_config.database).expand_path(Rails.root)
  end

  def snapshot(target)
    FileUtils.rm_f(target)
    db = SQLite3::Database.new(database_path.to_s, readonly: true)
    db.execute("VACUUM INTO ?", [ target.to_s ])
  ensure
    db&.close
  end

  def check!(path)
    db = SQLite3::Database.new(path.to_s, readonly: true)
    result = db.execute("PRAGMA quick_check")
    raise Failed, "quick_check failed for #{path.basename}: #{result.flatten.join('; ')}" unless result == [ [ "ok" ] ]
  ensure
    db&.close
  end
end
