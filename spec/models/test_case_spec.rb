require "rails_helper"

RSpec.describe TestCase do
  it "derives a stable key from file path and full name" do
    key = described_class.key_for("spec/a_spec.rb", "A works")
    expect(key).to eq(Digest::SHA256.hexdigest("spec/a_spec.rb\0A works"))
    expect(described_class.key_for("spec/a_spec.rb", "A works")).to eq(key)
    expect(described_class.key_for("spec/b_spec.rb", "A works")).not_to eq(key)
  end

  # The same vectors are pinned in raider_reporter spec/raider_reporter/test_key_spec.rb.
  it "matches the reporter's test_key vectors" do
    expect(described_class.key_for("spec/login_spec.rb", "Login works"))
      .to eq("8c60bc1f23271825db4e5abf04a43fcb67242e773ec55de36fff9fa9ae14de2a")
    expect(described_class.key_for("features/login.feature", "Login: A user is rejected"))
      .to eq("a3cf30d2a4844c2f019e8856215746a4a3ee51c5a8032d7eadef5da6e5d83212")
    expect(described_class.key_for("spec/a b_spec.rb", "Ünïcode → test"))
      .to eq("d370dd8cc44d6deff75f1e37427b88ad9a0fd8558c5dfc5ac943f80246ccead4")
  end
end
