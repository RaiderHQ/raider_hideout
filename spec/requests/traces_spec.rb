require "rails_helper"

RSpec.describe "Traces", type: :request do
  let(:member) { create(:user) }
  let(:project) { create(:project, organization: member.organizations.first) }
  let(:result) { create(:test_result, run: create(:run, project: project)) }
  let(:fixture) { file_fixture("trace-v1.zip").binread }
  let(:trace) { attach_trace(result, io: StringIO.new(fixture)) }

  describe "GET zip" do
    it "streams the zip to a member as a locked-down download" do
      sign_in(member)
      get test_result_trace_zip_path(result, trace)
      expect(response).to have_http_status(:ok)
      expect(response.body.b).to eq(fixture.b)
      expect(response.headers["Content-Type"]).to eq("application/octet-stream")
      expect(response.headers["Content-Disposition"]).to start_with("attachment")
      expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.headers["Content-Security-Policy"]).to eq("default-src 'none'; sandbox")
    end

    it "redirects signed-out users to sign in" do
      get test_result_trace_zip_path(result, trace)
      expect(response).to redirect_to(new_session_path)
    end

    it "404s for a non-member" do
      sign_in(create(:user))
      get test_result_trace_zip_path(result, trace)
      expect(response).to have_http_status(:not_found)
    end

    it "404s for a non-trace image/png attachment" do
      result.attachments.attach(io: StringIO.new("png"), filename: "s.png", content_type: "image/png")
      sign_in(member)
      get test_result_trace_zip_path(result, result.attachments.last)
      expect(response).to have_http_status(:not_found)
    end

    it "404s for a legacy application/zip attachment" do
      result.attachments.attach(io: StringIO.new(fixture), filename: "t.zip", content_type: "application/zip")
      sign_in(member)
      get test_result_trace_zip_path(result, result.attachments.last)
      expect(response).to have_http_status(:not_found)
    end

    it "404s when the attachment belongs to another result" do
      other = create(:test_result, run: result.run)
      sign_in(member)
      get test_result_trace_zip_path(other, trace)
      expect(response).to have_http_status(:not_found)
    end

    it "404s for an unknown id" do
      sign_in(member)
      get test_result_trace_zip_path(result, 0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
