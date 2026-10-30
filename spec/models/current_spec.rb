require "rails_helper"

RSpec.describe Current do
  after { described_class.reset }

  it "reads the user from the session, and prefers a user set directly (personal token requests)" do
    user = create(:user)
    other = create(:user)

    expect(described_class.user).to be_nil
    described_class.session = user.sessions.create!
    expect(described_class.user).to eq(user)

    described_class.user = other
    expect(described_class.user).to eq(other)
  end

  it "holds a user without any session" do
    user = create(:user)
    described_class.user = user
    expect(described_class.session).to be_nil
    expect(described_class.user).to eq(user)
  end
end
