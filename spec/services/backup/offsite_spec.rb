require "rails_helper"

RSpec.describe Backup::Offsite do
  let(:client) { Aws::S3::Client.new(stub_responses: true) }
  let(:offsite) { described_class.new(client: client, bucket: "backups") }
  let(:dir) { Pathname(Dir.mktmpdir) }

  def requests(operation) = client.api_requests.select { |request| request[:operation_name] == operation }

  def name_for(date) = date.strftime("raider-%Y%m%d-023000.sqlite3.gz")

  describe ".enabled?" do
    it "is on only when BACKUP_BUCKET is set" do
      expect(described_class.enabled?("BACKUP_BUCKET" => "backups")).to be(true)
      expect(described_class.enabled?("BACKUP_BUCKET" => " ")).to be(false)
      expect(described_class.enabled?({})).to be(false)
    end
  end

  describe "#upload" do
    it "puts the file under backups/ with its own name" do
      path = dir.join("raider-20261020-023000.sqlite3.gz")
      File.write(path, "gz")
      offsite.upload(path)
      put = requests(:put_object).sole
      expect(put[:params]).to include(bucket: "backups", key: "backups/raider-20261020-023000.sqlite3.gz")
    end

    it "raises Backup::Failed on a storage error and leaves the local file alone" do
      path = dir.join("raider-20261020-023000.sqlite3.gz")
      File.write(path, "gz")
      client.stub_responses(:put_object, "AccessDenied")
      expect { offsite.upload(path) }.to raise_error(Backup::Failed, /\Aoffsite upload: /)
      expect(path).to exist
    end

    it "raises Backup::Failed when the network is down" do
      path = dir.join("raider-20261020-023000.sqlite3.gz")
      File.write(path, "gz")
      client.stub_responses(:put_object, Seahorse::Client::NetworkingError.new(SocketError.new("down")))
      expect { offsite.upload(path) }.to raise_error(Backup::Failed, /offsite upload: down/)
    end
  end

  describe "#rotate" do
    it "deletes only backup files under backups/ that the keep rule drops" do
      names = (1..20).map { |n| name_for(Date.new(2026, 10, 20) - n) }
      foreign = [ "backups/notes.txt", "backups/old/#{names.last}", "other/#{names.last}" ]
      client.stub_responses(:list_objects_v2, contents: (names.map { |n| { key: "backups/#{n}" } } + foreign.map { |k| { key: k } }))
      offsite.rotate
      deleted = requests(:delete_object).map { |request| request[:params][:key] }
      expect(deleted).to match_array((names - Backup.keep(names)).map { |n| "backups/#{n}" })
      expect(deleted & foreign).to be_empty
      expect(requests(:list_objects_v2).first[:params]).to include(bucket: "backups", prefix: "backups/")
    end

    it "raises Backup::Failed when listing fails" do
      client.stub_responses(:list_objects_v2, "AccessDenied")
      expect { offsite.rotate }.to raise_error(Backup::Failed, /\Aoffsite rotate: /)
    end
  end

  describe "#fetch" do
    it "downloads the named backup into the directory with mode 0600" do
      client.stub_responses(:get_object, body: "gzdata")
      path = offsite.fetch("raider-20261020-023000.sqlite3.gz", dir)
      expect(path).to eq(dir.join("raider-20261020-023000.sqlite3.gz"))
      expect(path.read).to eq("gzdata")
      expect(path.stat.mode & 0o777).to eq(0o600)
      expect(requests(:get_object).sole[:params]).to include(key: "backups/raider-20261020-023000.sqlite3.gz")
    end

    [ "../../etc/passwd", "storage/backups/raider-20261020-023000.sqlite3.gz", "raider-latest.sqlite3.gz", "" ].each do |bad|
      it "rejects #{bad.inspect} before downloading anything" do
        expect { offsite.fetch(bad, dir) }.to raise_error(Backup::Failed, /pass the file name only/)
        expect(requests(:get_object)).to be_empty
      end
    end

    it "removes a partial file and raises Backup::Failed when the object is missing" do
      client.stub_responses(:get_object, "NoSuchKey")
      expect { offsite.fetch("raider-20261020-023000.sqlite3.gz", dir) }.to raise_error(Backup::Failed, /offsite fetch/)
      expect(dir.join("raider-20261020-023000.sqlite3.gz")).not_to exist
    end
  end
end
