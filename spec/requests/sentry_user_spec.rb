require "rails_helper"

RSpec.describe "Sentry user context", type: :request do
  # A DSN-less init is real but sends nothing; the Rack middleware needs a hub once
  # initialized? is true. Torn down so the rest of the suite sees Sentry off.
  before do
    Sentry.init { |config| config.dsn = nil }
    allow(Sentry).to receive(:set_user)
  end

  after { Sentry.instance_variable_set(:@main_hub, nil) }

  it "identifies a signed-in user by id only" do
    user = create(:user)
    sign_in(user)
    get root_path
    expect(Sentry).to have_received(:set_user).with(id: user.id)
  end

  it "sets no user for a visitor" do
    get new_session_path
    expect(Sentry).not_to have_received(:set_user)
  end
end
