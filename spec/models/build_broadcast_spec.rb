require "rails_helper"

RSpec.describe Build do
  include ActiveJob::TestHelper
  include ActionCable::TestHelper
  include ActionView::RecordIdentifier
  include Turbo::Streams::StreamName

  it "prepends new builds to the project's builds stream" do
    project = create(:project)
    expect { create(:build, project: project) }
      .to have_enqueued_job(Turbo::Streams::ActionBroadcastJob)
      .with(anything, hash_including(action: :prepend, target: "builds"))
  end

  it "renders the build partial when the job performs" do
    project = create(:project)
    stream = stream_name_from([ project, :builds ])
    build = nil
    perform_enqueued_jobs { build = create(:build, project: project, commit_message: "Ship the thing") }
    messages = ActionCable.server.pubsub.broadcasts(stream).map { |m| JSON.parse(m) }
    expect(messages.size).to eq(1)
    expect(messages.first).to include(dom_id(build), "Ship the thing", 'action="prepend"', 'target="builds"')
  end

  it "replaces the row when recompute! changes the build" do
    project = create(:project)
    build = create(:build, project: project)
    create(:run, project: project, build: build, status: "failed", failed_count: 2, total_count: 2)
    stream = stream_name_from([ project, :builds ])
    clear_enqueued_jobs
    perform_enqueued_jobs { build.reload.recompute! }
    messages = ActionCable.server.pubsub.broadcasts(stream).map { |m| JSON.parse(m) }
    replace = messages.find { |m| m.include?('action="replace"') }
    expect(replace).to include(dom_id(build), 'target="' + dom_id(build) + '"', "failed")
  end

  it "does not re-broadcast when recompute! changes nothing" do
    project = create(:project)
    build = create(:build, project: project)
    create(:run, project: project, build: build, status: "failed", failed_count: 2, total_count: 2)
    build.reload.recompute!
    clear_enqueued_jobs
    expect { build.reload.recompute! }.not_to have_enqueued_job(Turbo::Streams::ActionBroadcastJob)
  end
end
