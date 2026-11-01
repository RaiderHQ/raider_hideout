require "rails_helper"

RSpec.describe "Dropped attachments display", type: :request do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user) }
  let(:run) { create(:run, project: project) }

  before { sign_in(user) }

  def notices
    Nokogiri::HTML(response.body).css("[data-testid=dropped-attachment]").map { |node| node.text.squish }
  end

  it "says which files were not stored and why, on failed and passed results" do
    dropped = [ { "name" => "video", "content_type" => "video/webm", "bytes" => 62.megabytes, "limit" => 50.megabytes } ]
    create(:test_result, run: run, status: "failed", failure_message: "boom", dropped_attachments: dropped,
                         test_case: create(:test_case, project: project, full_name: "Fails"))
    create(:test_result, run: run, status: "passed",
                         dropped_attachments: [ { "name" => "log", "content_type" => "text/plain", "bytes" => 6.megabytes, "limit" => 5.megabytes } ],
                         test_case: create(:test_case, project: project, full_name: "Passes"))

    get project_run_path(project, run)

    expect(notices).to contain_exactly("video was not stored: 62 MB is over the 50 MB limit.",
                                       "log was not stored: 6 MB is over the 5 MB limit.")
  end

  it "shows nothing when every file was stored" do
    create(:test_result, run: run, status: "failed", failure_message: "boom",
                         test_case: create(:test_case, project: project, full_name: "Fails"))
    get project_run_path(project, run)
    expect(notices).to be_empty
  end
end
