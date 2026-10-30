require "rails_helper"

RSpec.describe "Attachments", type: :request do
  let(:member) { create(:user) }
  let(:project) { create(:project, organization: member.organizations.first) }
  let(:result) { create(:test_result, run: create(:run, project: project)) }

  def attach(io:, filename:, content_type:)
    result.attachments.attach(io: StringIO.new(io), filename: filename, content_type: content_type)
    result.attachments.last
  end

  it "streams an image inline to a member, with private caching and nosniff" do
    png = attach(io: "\x89PNG0123456789", filename: "shot.png", content_type: "image/png")
    sign_in(member)
    get attachment_path(png)
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to eq("\x89PNG0123456789".b)
    expect(response.headers["Content-Disposition"]).to start_with("inline")
    expect(response.headers["Cache-Control"]).to include("private")
    expect(response.headers["Cache-Control"]).to include("max-age=300")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "serves byte ranges for video seeking" do
    video = attach(io: "0123456789ABCDEF", filename: "run.webm", content_type: "video/webm")
    sign_in(member)
    get attachment_path(video), headers: { "Range" => "bytes=0-9" }
    expect(response).to have_http_status(:partial_content)
    expect(response.body).to eq("0123456789")
    expect(response.headers["Content-Disposition"]).to start_with("inline")
    expect(response.headers["Cache-Control"]).to include("private").and include("max-age=300")
    expect(response.headers["X-Content-Type-Options"]).to eq("nosniff")
  end

  it "forces a download for non-media files, even if they claim to be HTML" do
    html = attach(io: "<script>alert(1)</script>", filename: "x.html", content_type: "text/html")
    sign_in(member)
    get attachment_path(html)
    expect(response.headers["Content-Disposition"]).to start_with("attachment")
    expect(response.media_type).not_to eq("text/html")
  end

  it "forces a download for SVG and does not serve it as an image" do
    svg = attach(io: "<svg onload='alert(1)'/>", filename: "x.svg", content_type: "image/svg+xml")
    sign_in(member)
    get attachment_path(svg)
    expect(response.headers["Content-Disposition"]).to start_with("attachment")
    expect(response.media_type).not_to eq("image/svg+xml")
  end

  it "sandboxes served files with a locked-down CSP" do
    png = attach(io: "png", filename: "shot.png", content_type: "image/png")
    sign_in(member)
    get attachment_path(png)
    expect(response.headers["Content-Security-Policy"]).to eq("default-src 'none'; sandbox")
  end

  it "returns 404 when the test result behind the attachment is gone" do
    png = attach(io: "png", filename: "shot.png", content_type: "image/png")
    png.update_columns(record_id: 0)
    sign_in(member)
    get attachment_path(png)
    expect(response).to have_http_status(:not_found)
  end

  it "forces a download when asked, even for images" do
    png = attach(io: "png", filename: "shot.png", content_type: "image/png")
    sign_in(member)
    get attachment_path(png, disposition: "attachment")
    expect(response.headers["Content-Disposition"]).to start_with("attachment")
  end

  it "returns 404 to a user from another organization, even with the id" do
    png = attach(io: "png", filename: "shot.png", content_type: "image/png")
    sign_in(create(:user))
    get attachment_path(png)
    expect(response).to have_http_status(:not_found)
  end

  it "redirects signed-out users to sign in (ruling R2)" do
    png = attach(io: "png", filename: "shot.png", content_type: "image/png")
    get attachment_path(png)
    expect(response).to redirect_to(new_session_path)
  end

  it "returns 404 for attachments on records other than test results" do
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("x"), filename: "x.txt")
    other = ActiveStorage::Attachment.create!(name: "file", record: member, blob: blob)
    sign_in(member)
    get attachment_path(other)
    expect(response).to have_http_status(:not_found)
  end

  it "no longer exposes the public Active Storage routes" do
    png = attach(io: "png", filename: "shot.png", content_type: "image/png")
    path = "/rails/active_storage/blobs/redirect/#{png.blob.signed_id}/shot.png"
    get path
    expect(response).to have_http_status(:not_found)
  end

  context "when the blob lives in object storage (R2)" do
    let(:r2) do
      ActiveStorage::Service.configure(:r2, r2: {
        service: "S3", endpoint: "https://acct.r2.cloudflarestorage.com", region: "auto", bucket: "attachments",
        access_key_id: "test-key", secret_access_key: "test-secret", force_path_style: true, stub_responses: true
      })
    end

    # Every blob in these examples uses the stubbed S3 service: uploads hit the
    # aws-sdk stub, and URLs are presigned locally with the test credentials.
    before { allow_any_instance_of(ActiveStorage::Blob).to receive(:service).and_return(r2) }

    def signed_query
      expect(response).to have_http_status(:found)
      Rack::Utils.parse_query(URI.parse(response.location).query)
    end

    it "redirects a member to a 5-minute presigned URL that shows the image inline" do
      png = attach(io: "png", filename: "shot.png", content_type: "image/png")
      sign_in(member)
      get attachment_path(png)
      location = URI.parse(response.location)
      query = signed_query
      expect(location.host).to eq("acct.r2.cloudflarestorage.com")
      expect(location.path).to eq("/attachments/#{png.blob.key}")
      expect(query["X-Amz-Expires"]).to eq("300")
      expect(query["response-content-disposition"]).to start_with("inline")
      expect(query["response-content-type"]).to eq("image/png")
      expect(response.headers["Cache-Control"]).to eq("private, no-store")
    end

    # Production configures only the S3 service, so Active Storage never loads DiskService.
    it "works when the Disk service class is not loaded" do
      hide_const("ActiveStorage::Service::DiskService")
      png = attach(io: "png", filename: "shot.png", content_type: "image/png")
      sign_in(member)
      get attachment_path(png)
      expect(signed_query["response-content-disposition"]).to start_with("inline")
    end

    it "signs a download, never text/html, for HTML" do
      html = attach(io: "<script>alert(1)</script>", filename: "x.html", content_type: "text/html")
      sign_in(member)
      get attachment_path(html)
      query = signed_query
      expect(query["response-content-disposition"]).to start_with("attachment")
      expect(query["response-content-type"]).not_to eq("text/html")
    end

    it "signs a download, never image/svg+xml, for SVG" do
      svg = attach(io: "<svg onload='alert(1)'/>", filename: "x.svg", content_type: "image/svg+xml")
      sign_in(member)
      get attachment_path(svg)
      query = signed_query
      expect(query["response-content-disposition"]).to start_with("attachment")
      expect(query["response-content-type"]).not_to eq("image/svg+xml")
    end

    it "signs a download for files outside the inline allowlist" do
      pdf = attach(io: "%PDF-1.7", filename: "report.pdf", content_type: "application/pdf")
      sign_in(member)
      get attachment_path(pdf)
      expect(signed_query["response-content-disposition"]).to start_with("attachment")
    end

    it "signs a download when asked, even for images" do
      png = attach(io: "png", filename: "shot.png", content_type: "image/png")
      sign_in(member)
      get attachment_path(png, disposition: "attachment")
      expect(signed_query["response-content-disposition"]).to start_with("attachment")
    end

    it "keeps non-ASCII and spaced filenames intact in the signed disposition" do
      png = attach(io: "png", filename: "résumé shot.png", content_type: "image/png")
      sign_in(member)
      get attachment_path(png)
      expect(signed_query["response-content-disposition"]).to include("filename*=UTF-8''r%C3%A9sum%C3%A9%20shot.png")
    end

    it "returns 404 to a user from another organization, without a redirect" do
      png = attach(io: "png", filename: "shot.png", content_type: "image/png")
      sign_in(create(:user))
      get attachment_path(png)
      expect(response).to have_http_status(:not_found)
      expect(response.location).to be_nil
    end
  end
end
