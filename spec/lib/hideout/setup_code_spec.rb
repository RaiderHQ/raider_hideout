require "rails_helper"

RSpec.describe Hideout::SetupCode do
  after { described_class.reset! }

  it "generates one 8-character code per process from an unambiguous alphabet" do
    code = described_class.current({})
    expect(code).to match(/\A[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}\z/)
    expect(described_class.current({})).to eq(code)
    expect(described_class.display({})).to eq("#{code[0, 4]}-#{code[4, 4]}")
  end

  it "uses HIDEOUT_SETUP_CODE when set" do
    env = { "HIDEOUT_SETUP_CODE" => "abcd-2345" }
    expect(described_class.current(env)).to eq("ABCD2345")
    expect(described_class.display(env)).to eq("ABCD-2345")
  end

  it "accepts the code as a person types it" do
    env = { "HIDEOUT_SETUP_CODE" => "ABCD-2345" }
    [ "ABCD-2345", "abcd2345", " abcd-2345 ", "AB CD 23 45" ].each do |typed|
      expect(described_class.valid?(typed, env)).to be(true), typed
    end
  end

  it "rejects a wrong, empty or partial code" do
    env = { "HIDEOUT_SETUP_CODE" => "ABCD-2345" }
    [ nil, "", "ABCD-2346", "ABCD", "ABCD-23456" ].each do |typed|
      expect(described_class.valid?(typed, env)).to be(false), typed.inspect
    end
  end

  it "announces the setup link with the instance's base URL" do
    env = { "HIDEOUT_SETUP_CODE" => "ABCD-2345", "APP_HOST" => "localhost:3010", "HIDEOUT_FORCE_SSL" => "false" }
    expect(described_class.announcement(env, rails_env: ActiveSupport::StringInquirer.new("production")))
      .to eq("[hideout] no users yet: open http://localhost:3010/setup?code=ABCD-2345 to create the first admin")
  end
end
