require "rails_helper"

RSpec.describe "test_results/_card", type: :view do
  let(:project) { create(:project) }
  let(:run) { create(:run, project: project) }
  let(:fixture) { file_fixture("trace-v1.zip").binread }

  def render_card(result)
    render partial: "test_results/card", locals: { result: result }
  end

  %w[passed failed].each do |status|
    it "links to the viewer for a #{status} result, and not as a plain download" do
      result = create(:test_result, run: run, status: status)
      trace = attach_trace(result, io: StringIO.new(fixture))
      render_card(result)
      link = Capybara.string(rendered).find("a", text: "Open trace", visible: :all)
      expect(link[:href]).to eq(test_result_trace_path(result, trace))
      expect(link["data-turbo"]).to eq("false")
      expect(link["data-turbo-prefetch"]).to eq("false")
      expect(rendered).not_to include(attachment_path(trace))
    end
  end

  it "lists two traces newest first with counts" do
    result = create(:test_result, run: run, status: "passed")
    older = attach_trace(result, io: StringIO.new(fixture), filename: "a.zip")
    older.update_columns(created_at: 2.hours.ago)
    newer = attach_trace(result, io: StringIO.new(fixture), filename: "b.zip")
    render_card(result)
    links = Capybara.string(rendered).all("a", text: "Open trace", visible: :all)
    expect(links.map { |l| l[:href] }).to eq([ test_result_trace_path(result, newer), test_result_trace_path(result, older) ])
    expect(links.map { |l| l.text(:all) }).to eq([ "Open trace (1 of 2)", "Open trace (2 of 2)" ])
  end

  it "offers no link for a legacy application/zip attachment" do
    result = create(:test_result, run: run, status: "failed")
    result.attachments.attach(io: StringIO.new(fixture), filename: "t.zip", content_type: "application/zip")
    render_card(result)
    expect(rendered).not_to include("Open trace")
  end
end
