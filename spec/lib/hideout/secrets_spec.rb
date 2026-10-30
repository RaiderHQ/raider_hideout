require "rails_helper"

RSpec.describe Hideout::Secrets do
  let(:root) { Pathname(Dir.mktmpdir) }
  let(:err) { StringIO.new }
  let(:file) { root.join("storage/hideout-secrets.yml") }

  after { FileUtils.remove_entry(root) }

  def load(env = {}, rails_env: "production")
    described_class.load!(env: env, root: root.to_s, rails_env: rails_env, err: err)
  end

  it "generates every missing key into a 0600 file and fills the environment" do
    env = {}
    expect(load(env)).to match_array(described_class::NAMES)
    expect(File.stat(file).mode & 0o777).to eq(0o600)
    stored = YAML.safe_load(file.read)
    expect(stored.keys).to match_array(described_class::NAMES)
    expect(env).to eq(stored)
    expect(env["SECRET_KEY_BASE"]).to match(/\A\h{128}\z/)
    expect(env["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]).to match(/\A[A-Za-z0-9]{32}\z/)
    expect(err.string).to eq("[hideout] generated secrets in #{file}; back this file up with your database\n")
  end

  it "reuses the file on the next boot without printing anything" do
    first = {}
    load(first)
    described_class.check_existing_data!(has_users: false)
    err.truncate(0)
    second = {}
    expect(load(second)).to eq([])
    expect(second).to eq(first)
    expect(err.string).to be_empty
  end

  it "lets the environment win and writes no file when every key is set" do
    env = described_class::NAMES.index_with { |name| "from-env-#{name}" }
    expect(load(env)).to eq([])
    expect(file).not_to exist
    expect(env["SECRET_KEY_BASE"]).to eq("from-env-SECRET_KEY_BASE")
  end

  it "only stores the keys the environment does not provide" do
    env = { "SECRET_KEY_BASE" => "from-env" }
    load(env)
    expect(YAML.safe_load(file.read).keys).to match_array(described_class::NAMES - [ "SECRET_KEY_BASE" ])
    expect(env["SECRET_KEY_BASE"]).to eq("from-env")
  end

  it "fills a partial file and keeps its existing values" do
    FileUtils.mkdir_p(file.dirname)
    file.write({ "SECRET_KEY_BASE" => "kept" }.to_yaml)
    env = {}
    expect(load(env)).to match_array(described_class::NAMES - [ "SECRET_KEY_BASE" ])
    expect(env["SECRET_KEY_BASE"]).to eq("kept")
    expect(YAML.safe_load(file.read)["SECRET_KEY_BASE"]).to eq("kept")
  end

  [ "- a\n- list\n", "SECRET_KEY_BASE: 12\n", "SECRET_KEY_BASE: [unclosed\n" ].each do |content|
    it "stops boot on an unreadable file (#{content.inspect})" do
      FileUtils.mkdir_p(file.dirname)
      file.write(content)
      expect { load({}) }.to raise_error(described_class::Unreadable, /\A\[hideout\] cannot read secrets file #{Regexp.escape(file.to_s)}: /)
    end
  end

  it "stops boot when the directory cannot be written" do
    FileUtils.mkdir_p(file.dirname)
    File.chmod(0o500, file.dirname)
    expect { load({}) }.to raise_error(described_class::Unreadable, /\A\[hideout\] cannot write secrets file #{Regexp.escape(file.to_s)}: /)
  ensure
    File.chmod(0o700, file.dirname)
  end

  it "does nothing outside production or during asset precompilation" do
    expect(load({}, rails_env: "test")).to eq([])
    expect(load({ "SECRET_KEY_BASE_DUMMY" => "1" })).to eq([])
    expect(file).not_to exist
  end

  it "reads HIDEOUT_SECRETS_FILE relative to the app root or as an absolute path" do
    load({ "HIDEOUT_SECRETS_FILE" => "config/keys.yml" })
    expect(root.join("config/keys.yml")).to exist
    absolute = root.join("elsewhere/keys.yml").to_s
    load({ "HIDEOUT_SECRETS_FILE" => absolute })
    expect(File).to exist(absolute)
  end

  it "waits for another process holding the lock and uses what it wrote" do
    FileUtils.mkdir_p(file.dirname)
    written = described_class::NAMES.index_with { |name| "other-#{name}" }
    lock = File.open("#{file}.lock", File::RDWR | File::CREAT, 0o600)
    lock.flock(File::LOCK_EX)
    loader = Thread.new do
      env = {}
      [ load(env), env ]
    end
    sleep 0.2
    file.write(written.to_yaml)
    lock.flock(File::LOCK_UN)
    lock.close
    generated, env = loader.value
    expect(generated).to eq([])
    expect(env).to eq(written)
  end

  describe "keys generated on an install that already has data" do
    it "moves a brand-new file aside and refuses to boot" do
      load({})
      expect { described_class.check_existing_data!(has_users: true) }
        .to raise_error(described_class::Unreadable, /generated new secrets in .* but the database already has users/)
      expect(file).not_to exist
      expect(Pathname("#{file}.rejected")).to exist
    end

    it "restores the previous content of a partial file" do
      FileUtils.mkdir_p(file.dirname)
      file.write({ "SECRET_KEY_BASE" => "kept" }.to_yaml)
      load({})
      expect { described_class.check_existing_data!(has_users: true) }.to raise_error(described_class::Unreadable)
      expect(YAML.safe_load(file.read)).to eq("SECRET_KEY_BASE" => "kept")
    end

    it "does not keep generated keys when the database could not be checked" do
      load({})
      expect { described_class.check_existing_data!(has_users: :unknown) }
        .to raise_error(described_class::Unreadable, /could not reach the database to confirm a fresh install/)
      expect(file).not_to exist
    end

    let(:sidecar) { Pathname("#{file}.unconfirmed") }

    it "writes a 0600 sidecar naming the generated keys until the install is confirmed" do
      load({})
      expect(File.stat(sidecar).mode & 0o777).to eq(0o600)
      expect(YAML.safe_load(sidecar.read)).to eq("generated" => described_class::NAMES, "previous" => nil)
      described_class.check_existing_data!(has_users: false)
      expect(sidecar).not_to exist
      expect(file).to exist
    end

    it "still refuses on the next boot when the first one stopped before the check" do
      load({})
      second = {}
      expect(load(second)).to match_array(described_class::NAMES)
      expect(err.string.scan("generated secrets").size).to eq(1)
      expect { described_class.check_existing_data!(has_users: true) }
        .to raise_error(described_class::Unreadable, /generated new secrets in .* but the database already has users/)
      expect(file).not_to exist
      expect(Pathname("#{file}.rejected")).to exist
      expect(sidecar).not_to exist
    end

    it "restores the content from before the first boot when a later boot finds users" do
      FileUtils.mkdir_p(file.dirname)
      file.write({ "SECRET_KEY_BASE" => "kept" }.to_yaml)
      load({})
      expect(load({})).to match_array(described_class::NAMES - [ "SECRET_KEY_BASE" ])
      expect { described_class.check_existing_data!(has_users: :unknown) }
        .to raise_error(described_class::Unreadable, /could not reach the database/)
      expect(YAML.safe_load(file.read)).to eq("SECRET_KEY_BASE" => "kept")
      expect(sidecar).not_to exist
    end

    it "stops boot on an unreadable sidecar" do
      load({})
      sidecar.write("- a\n- list\n")
      expect { load({}) }.to raise_error(described_class::Unreadable, /cannot read #{Regexp.escape(sidecar.to_s)}/)
    end

    it "lets a fresh install or a boot that generated nothing through" do
      load({})
      expect(described_class.check_existing_data!(has_users: false)).to be_nil
      load({})
      expect(described_class.check_existing_data!(has_users: true)).to be_nil
    end
  end
end
