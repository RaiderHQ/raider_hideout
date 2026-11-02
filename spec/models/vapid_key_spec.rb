require "rails_helper"

RSpec.describe VapidKey do
  let(:env_names) { %w[HIDEOUT_VAPID_PUBLIC_KEY HIDEOUT_VAPID_PRIVATE_KEY HIDEOUT_VAPID_SUBJECT] }

  around do |example|
    saved = env_names.index_with { |n| ENV[n] }
    env_names.each { |n| ENV.delete(n) }
    example.run
  ensure
    saved.each { |n, v| v ? ENV[n] = v : ENV.delete(n) }
  end

  it "generates a pair on first use and returns the same pair afterwards" do
    first = described_class.current
    expect(first.public_key).to be_present
    expect(first.private_key).to be_present
    expect(described_class.current).to eq(first)
    expect(described_class.count).to eq(1)
  end

  it "stores the private key encrypted" do
    pair = described_class.current
    raw = described_class.connection.select_value("SELECT private_key FROM vapid_keys")
    expect(raw).not_to include(pair.private_key)
    expect(described_class.first.private_key).to eq(pair.private_key)
  end

  it "never regenerates when a row exists" do
    existing = described_class.create!(name: "default", public_key: "pub", private_key: "priv")
    expect(WebPush).not_to receive(:generate_key)
    pair = described_class.current
    expect([ pair.public_key, pair.private_key ]).to eq(%w[pub priv])
    expect(described_class.count).to eq(1)
    expect(existing.reload.public_key).to eq("pub")
  end

  it "returns the winner's row when another process inserts between find and create" do
    winner = nil
    allow(WebPush).to receive(:generate_key).and_wrap_original do |original|
      winner ||= described_class.create!(name: "default", public_key: "winner-pub", private_key: "winner-priv")
      original.call
    end
    pair = described_class.current
    expect(described_class.count).to eq(1)
    expect(pair.public_key).to eq("winner-pub")
    expect(pair.private_key).to eq("winner-priv")
  end

  describe "env override" do
    before do
      ENV["HIDEOUT_VAPID_PUBLIC_KEY"] = "env-pub"
      ENV["HIDEOUT_VAPID_PRIVATE_KEY"] = "env-priv"
    end

    it "uses the env pair and stores nothing" do
      pair = described_class.current
      expect([ pair.public_key, pair.private_key ]).to eq(%w[env-pub env-priv])
      expect(described_class.count).to eq(0)
    end

    it "uses HIDEOUT_VAPID_SUBJECT when set" do
      ENV["HIDEOUT_VAPID_SUBJECT"] = "mailto:ops@example.com"
      expect(described_class.current.subject).to eq("mailto:ops@example.com")
    end
  end

  describe "half-configured env" do
    it "names the missing private variable" do
      ENV["HIDEOUT_VAPID_PUBLIC_KEY"] = "env-pub"
      expect { described_class.current }.to raise_error(VapidKey::Misconfigured, /HIDEOUT_VAPID_PRIVATE_KEY/)
    end

    it "names the missing public variable" do
      ENV["HIDEOUT_VAPID_PRIVATE_KEY"] = "env-priv"
      expect { described_class.current }.to raise_error(VapidKey::Misconfigured, /HIDEOUT_VAPID_PUBLIC_KEY/)
    end
  end

  describe "subject" do
    it "falls back to the project URL with no owner" do
      create(:membership, role: "admin")
      Membership.where(role: "owner").delete_all # users get a personal-org owner membership by default
      expect(described_class.current.subject).to eq("https://github.com/RaiderHQ/raider_hideout")
    end

    it "uses the earliest owner's email" do
      later = create(:membership, role: "owner", created_at: 1.day.ago)
      earliest = create(:membership, role: "owner", created_at: 3.days.ago)
      create(:membership, role: "admin", created_at: 5.days.ago)
      expect(described_class.current.subject).to eq("mailto:#{earliest.user.email_address}")
      expect(later).to be_persisted
    end
  end

  describe ".rotate!" do
    it "replaces the stored pair and returns the number of subscriptions deleted" do
      old = described_class.current
      expect(described_class.rotate!).to eq(0)
      fresh = described_class.current
      expect(fresh.public_key).not_to eq(old.public_key)
      expect(described_class.count).to eq(1)
    end

    it "generates a pair when none exists yet" do
      expect(described_class.rotate!).to eq(0)
      expect(described_class.count).to eq(1)
    end
  end

  it "leaves the boot secrets list unchanged" do
    expect(Hideout::Secrets::NAMES).to eq(%w[
      SECRET_KEY_BASE
      ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
      ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
      ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    ])
  end
end
