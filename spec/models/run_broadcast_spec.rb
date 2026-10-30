require "rails_helper"

RSpec.describe Run do
  include ActiveJob::TestHelper
  include ActionCable::TestHelper
  include ActionView::RecordIdentifier
  include Turbo::Streams::StreamName

  it "broadcasts new runs to the project's runs stream" do
    project = create(:project)
    expect { create(:run, project: project) }
      .to have_enqueued_job(Turbo::Streams::ActionBroadcastJob)
      .with(anything, hash_including(action: :prepend, target: "runs"))
  end

  it "renders the run partial outside a request when the job performs" do
    project = create(:project)
    stream = stream_name_from([ project, :runs ])
    run = nil
    perform_enqueued_jobs { run = create(:run, project: project, commit_message: "Ship the thing") }
    messages = ActionCable.server.pubsub.broadcasts(stream).map { |m| JSON.parse(m) }
    expect(messages.size).to eq(1)
    expect(messages.first).to include(dom_id(run), "Ship the thing", 'action="prepend"', 'target="runs"')
  end
end
