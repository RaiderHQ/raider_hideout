require "rails_helper"

RSpec.describe "Sentry initializer" do
  it "leaves Sentry off when SENTRY_DSN is not set" do
    expect(ENV["SENTRY_DSN"]).to be_blank
    expect(Sentry.initialized?).to be(false)
  end

  it "sends no personal data, no traces by default, and scrubs every event" do
    config = nil
    allow(Sentry).to receive(:init) { |&block| block.call(config = Sentry::Configuration.new) }
    stub_const("ENV", ENV.to_h.merge("SENTRY_DSN" => "https://key@o1.ingest.de.sentry.io/1", "KAMAL_VERSION" => "abc123"))
    load Rails.root.join("config/initializers/sentry.rb")
    expect(config.send_default_pii).to be(false)
    expect(config.traces_sample_rate).to eq(0.0)
    expect(config.release).to eq("abc123")
    event = Struct.new(:request).new(nil)
    expect(config.before_send.call(event, {})).to be(event)
  end
end
