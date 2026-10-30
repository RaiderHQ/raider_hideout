require "rails_helper"

RSpec.describe ProjectStreamsChannel, type: :channel do
  include ActionCable::TestHelper
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:project) { create(:project, owner: owner) }
  let(:outsider) { create(:user) }

  def signed(*streamables)
    Turbo::StreamsChannel.signed_stream_name(streamables)
  end

  it "subscribes a member to the project's stream" do
    stub_connection current_user: owner
    subscribe signed_stream_name: signed(project, :builds)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(Turbo::StreamsChannel.send(:stream_name_from, [ project, :builds ]))
  end

  it "subscribes a viewer of the project's organization" do
    viewer = create(:user)
    create(:membership, organization: project.organization, user: viewer, role: "viewer")
    stub_connection current_user: viewer
    subscribe signed_stream_name: signed(project, :runs)
    expect(subscription).to be_confirmed
  end

  it "rejects a non-member even with a valid signed name" do
    stub_connection current_user: outsider
    subscribe signed_stream_name: signed(project, :builds)
    expect(subscription).to be_rejected
  end

  it "rejects a removed member" do
    membership = create(:membership, organization: project.organization, user: outsider, role: "member")
    membership.destroy!
    stub_connection current_user: outsider
    subscribe signed_stream_name: signed(project, :builds)
    expect(subscription).to be_rejected
  end

  it "rejects a tampered or unsigned name" do
    stub_connection current_user: owner
    subscribe signed_stream_name: "#{project.to_gid_param}:builds"
    expect(subscription).to be_rejected
  end

  it "rejects a stream for a deleted project" do
    name = signed(project, :builds)
    project.destroy!
    stub_connection current_user: owner
    subscribe signed_stream_name: name
    expect(subscription).to be_rejected
  end

  it "receives model broadcasts on the same stream" do
    stub_connection current_user: owner
    subscribe signed_stream_name: signed(project, :builds)
    stream = Turbo::StreamsChannel.send(:stream_name_from, [ project, :builds ])
    perform_enqueued_jobs { create(:build, project: project) }
    expect(broadcasts(stream)).not_to be_empty
  end
end
