require "rails_helper"
require "rake"

RSpec.describe "hideout:vapid:rotate" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "hideout:vapid:rotate" } }

  around do |example|
    saved = %w[HIDEOUT_VAPID_PUBLIC_KEY HIDEOUT_VAPID_PRIVATE_KEY].index_with { |n| ENV[n] }
    saved.each_key { |n| ENV.delete(n) }
    example.run
  ensure
    saved.each { |n, v| v ? ENV[n] = v : ENV.delete(n) }
  end

  it "replaces the pair and prints how many devices must subscribe again" do
    old = VapidKey.current
    allow(VapidKey).to receive(:rotate!).and_wrap_original { |m| m.call; 3 }
    task = Rake::Task["hideout:vapid:rotate"]
    task.reenable
    expect { task.invoke }.to output("Rotated the VAPID keys. 3 devices must turn on phone notifications again.\n").to_stdout
    expect(VapidKey.current.public_key).not_to eq(old.public_key)
  end

  it "deletes every subscription and prints how many devices must subscribe again" do
    2.times do |i|
      create(:user).push_subscriptions.create!(endpoint: "https://fcm.googleapis.com/fcm/send/#{i}",
        p256dh: Base64.urlsafe_encode64("\x04".b + "a" * 64, padding: false), auth: Base64.urlsafe_encode64("b" * 16, padding: false))
    end
    task = Rake::Task["hideout:vapid:rotate"]
    task.reenable
    expect { task.invoke }.to output("Rotated the VAPID keys. 2 devices must turn on phone notifications again.\n").to_stdout
    expect(PushSubscription.count).to eq(0)
  end

  it "refuses to rotate when the pair comes from the environment" do
    ENV["HIDEOUT_VAPID_PUBLIC_KEY"] = "env-pub"
    ENV["HIDEOUT_VAPID_PRIVATE_KEY"] = "env-priv"
    expect(VapidKey).not_to receive(:rotate!)
    task = Rake::Task["hideout:vapid:rotate"]
    task.reenable
    expect { task.invoke }.to raise_error(SystemExit) { |e| expect(e.status).not_to eq(0) }
      .and output("The VAPID keys come from HIDEOUT_VAPID_PUBLIC_KEY and HIDEOUT_VAPID_PRIVATE_KEY. Change them there; nothing was rotated or deleted.\n").to_stderr
  end
end
