require "rails_helper"

RSpec.describe PushSubscription, type: :model do
  let(:user) { create(:user) }

  def build_subscription(**attrs)
    described_class.new({ user: user, endpoint: fcm_endpoint, p256dh: valid_p256dh, auth: valid_auth }.merge(attrs))
  end

  around do |example|
    saved = ENV["HIDEOUT_PUSH_HOSTS"]
    ENV.delete("HIDEOUT_PUSH_HOSTS")
    example.run
  ensure
    saved ? ENV["HIDEOUT_PUSH_HOSTS"] = saved : ENV.delete("HIDEOUT_PUSH_HOSTS")
  end

  describe ".allowed_endpoint?" do
    [
      "https://fcm.googleapis.com/fcm/send/abc",
      "https://FCM.googleapis.com:443/fcm/send/abc",
      "https://web.push.apple.com/QWERTY",
      "https://updates.push.services.mozilla.com/wpush/v2/abc",
      "https://par02p.notify.windows.com/w/?token=abc"
    ].each do |url|
      it("accepts #{url}") { expect(described_class.allowed_endpoint?(url)).to be(true) }
    end

    [
      "http://fcm.googleapis.com/fcm/send/abc",
      "https://10.0.0.1/fcm/send/abc",
      "https://[::1]/x",
      "https://[2001:db8::1]/x",
      "https://2130706433/x",
      "https://fcm.googleapis.com:8443/fcm/send/abc",
      "https://evil.example/fcm/send/abc",
      "https://fcm.googleapis.com.evil.example/x",
      "https://evilfcm.googleapis.com/x",
      "https://push.apple.com/x",
      "https://evilpush.apple.com/x",
      "https://user:pw@fcm.googleapis.com/x",
      "https://fcm.googleapis.com@evil.example/x",
      "https://.push.apple.com/x",
      "https://a..push.apple.com/x",
      "https://a%2f.push.apple.com/x",
      "https://a_b.push.apple.com/x",
      "https://a b.push.apple.com/x",
      "javascript:alert(1)",
      "not a url",
      "",
      nil
    ].each do |url|
      it("rejects #{url.inspect}") { expect(described_class.allowed_endpoint?(url)).to be(false) }
    end

    it "accepts extra hosts from HIDEOUT_PUSH_HOSTS, read at call time, with the same wildcard rule" do
      expect(described_class.allowed_endpoint?("https://push.example.org/x")).to be(false)
      ENV["HIDEOUT_PUSH_HOSTS"] = " Push.Example.org , *.relay.example.net "
      expect(described_class.allowed_endpoint?("https://push.example.org/x")).to be(true)
      expect(described_class.allowed_endpoint?("https://a.relay.example.net/x")).to be(true)
      expect(described_class.allowed_endpoint?("https://relay.example.net/x")).to be(false)
      expect(described_class.allowed_endpoint?("https://evilrelay.example.net/x")).to be(false)
      expect(described_class.allowed_endpoint?("https://10.0.0.1/x")).to be(false)
    end
  end

  describe "validations" do
    it "is valid with an FCM endpoint and well-formed keys" do
      expect(build_subscription).to be_valid
    end

    it "rejects an endpoint on an unknown host, even with good keys" do
      sub = build_subscription(endpoint: "https://evil.example/x")
      expect(sub).not_to be_valid
      expect(sub.errors[:endpoint]).to be_present
    end

    it "rejects an endpoint over 2,000 characters" do
      expect(build_subscription(endpoint: fcm_endpoint("a" * 2000))).not_to be_valid
    end

    it "rejects keys of the wrong length or alphabet" do
      expect(build_subscription(p256dh: b64url(Array.new(64, 1)))).not_to be_valid
      expect(build_subscription(auth: b64url(Array.new(15, 1)))).not_to be_valid
      expect(build_subscription(p256dh: "!!!")).not_to be_valid
      expect(build_subscription(auth: nil)).not_to be_valid
    end

    it "limits the device label to 60 characters" do
      expect(build_subscription(device_label: "x" * 61)).not_to be_valid
    end

    it "keeps one row per endpoint" do
      build_subscription.save!
      expect(build_subscription(user: create(:user))).not_to be_valid
    end
  end

  describe ".label_from_user_agent" do
    it "names the device from the User-Agent" do
      expect(described_class.label_from_user_agent("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0)")).to eq("iPhone")
      expect(described_class.label_from_user_agent("Mozilla/5.0 (iPad; CPU OS 17_0)")).to eq("iPad")
      expect(described_class.label_from_user_agent("Mozilla/5.0 (Linux; Android 14)")).to eq("Android")
      expect(described_class.label_from_user_agent("Mozilla/5.0 (Macintosh; Intel Mac OS X)")).to eq("Mac")
      expect(described_class.label_from_user_agent("curl/8")).to eq("Browser")
      expect(described_class.label_from_user_agent(nil)).to eq("Browser")
    end
  end

  describe "User#push_preference!" do
    it "creates the defaults row once" do
      pref = user.push_preference!
      expect(pref).to have_attributes(default_branch_failures: true, rerun_results: true, new_flaky: false, gate_failures: false)
      expect(user.push_preference!.id).to eq(pref.id)
    end

    it "deletes subscriptions, preference and muted rows with the user" do
      build_subscription.save!
      user.push_preference!
      project = create(:project, owner: user)
      user.push_muted_projects.create!(project: project)
      expect { user.destroy! }.to change { [ PushSubscription.count, PushPreference.count, PushMutedProject.count ] }.to([ 0, 0, 0 ])
    end
  end
end
