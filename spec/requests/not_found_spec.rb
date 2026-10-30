require "rails_helper"

RSpec.describe "Not found", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "renders the branded page for HTML" do
    get project_path("missing-project")
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Page not found")
  end

  it "renders the branded page for Turbo requests" do
    get project_path("missing-project"),
        headers: { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }
    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Page not found")
  end

  it "returns an empty 404 for JSON" do
    get project_path("missing-project", format: :json)
    expect(response).to have_http_status(:not_found)
    expect(response.body).to be_empty
  end

  it "ships static error pages with no external URLs" do
    %w[404 422 500].each do |code|
      html = Rails.public_path.join("#{code}.html").read
      expect(html).to include("#C14420")
      expect(html.scan(%r{https?://})).to be_empty
    end
  end
end
