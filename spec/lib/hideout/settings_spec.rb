require "rails_helper"

RSpec.describe Hideout do
  let(:production) { ActiveSupport::StringInquirer.new("production") }

  describe ".open_signup?" do
    it "is false by default and for anything but a true value" do
      expect(described_class.open_signup?({})).to be(false)
      [ "false", "0", "no", "", "on", "enabled" ].each do |value|
        expect(described_class.open_signup?("HIDEOUT_OPEN_SIGNUP" => value)).to be(false), value
      end
    end

    it "accepts true, 1 and yes in any case, with spaces" do
      [ "true", "TRUE", " 1 ", "Yes" ].each do |value|
        expect(described_class.open_signup?("HIDEOUT_OPEN_SIGNUP" => value)).to be(true), value
      end
    end
  end

  describe ".force_ssl?" do
    it "is on unless explicitly turned off" do
      expect(described_class.force_ssl?({})).to be(true)
      expect(described_class.force_ssl?("HIDEOUT_FORCE_SSL" => "maybe")).to be(true)
      [ "false", "0", " NO " ].each do |value|
        expect(described_class.force_ssl?("HIDEOUT_FORCE_SSL" => value)).to be(false), value
      end
    end

    it "sets the URL protocol" do
      expect(described_class.url_protocol({})).to eq("https")
      expect(described_class.url_protocol("HIDEOUT_FORCE_SSL" => "false")).to eq("http")
    end
  end

  describe ".assume_ssl?" do
    it "is off unless a header-less TLS proxy is declared" do
      expect(described_class.assume_ssl?({})).to be(false)
      expect(described_class.assume_ssl?("HIDEOUT_ASSUME_SSL" => "maybe")).to be(false)
      expect(described_class.assume_ssl?("HIDEOUT_ASSUME_SSL" => " TRUE ")).to be(true)
    end
  end

  describe ".mail_enabled?" do
    it "follows SMTP_ADDRESS in production" do
      expect(described_class.mail_enabled?({}, rails_env: production)).to be(false)
      expect(described_class.mail_enabled?({ "SMTP_ADDRESS" => " " }, rails_env: production)).to be(false)
      expect(described_class.mail_enabled?({ "SMTP_ADDRESS" => "smtp.example.com" }, rails_env: production)).to be(true)
    end

    it "is on in development and test" do
      expect(described_class.mail_enabled?({}, rails_env: ActiveSupport::StringInquirer.new("test"))).to be(true)
      expect(described_class.mail_enabled?({}, rails_env: ActiveSupport::StringInquirer.new("development"))).to be(true)
    end
  end

  describe ".host_name and .base_url" do
    it "drops the port for host authorization but keeps it in the endpoint" do
      env = { "APP_HOST" => "localhost:3010", "HIDEOUT_FORCE_SSL" => "false" }
      expect(described_class.host_name(env)).to eq("localhost")
      expect(described_class.base_url(env, rails_env: production)).to eq("http://localhost:3010")
    end

    it "uses https in production unless HTTPS is off" do
      expect(described_class.base_url({ "APP_HOST" => "hideout.example.com" }, rails_env: production))
        .to eq("https://hideout.example.com")
    end

    it "falls back to localhost and PORT outside production" do
      expect(described_class.base_url({ "PORT" => "3001" }, rails_env: ActiveSupport::StringInquirer.new("development")))
        .to eq("http://localhost:3001")
    end

    it "treats an empty PORT as unset" do
      expect(described_class.base_url({ "PORT" => " " }, rails_env: ActiveSupport::StringInquirer.new("development")))
        .to eq("http://localhost:3000")
    end
  end
end
