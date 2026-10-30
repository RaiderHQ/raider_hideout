require "rails_helper"

RSpec.describe "OpenAPI document", type: :request do
  let(:document) { OpenApiHelpers.document }

  it "is valid OpenAPI 3.1 with a bearer scheme applied to every operation" do
    expect(document["openapi"]).to eq("3.1.0")
    expect(OpenApiHelpers.openapi.validate.map { |error| error["error"] }).to be_empty
    expect(document.dig("components", "securitySchemes", "bearerAuth")).to include("type" => "http", "scheme" => "bearer")
    expect(document["security"]).to eq([ { "bearerAuth" => [] } ])
  end

  it "documents exactly the routes under /api/v1/projects" do
    routes = Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      path.gsub(/:(\w+)/, '{\1}') if path.start_with?("/api/v1/projects")
    end
    expect(routes.uniq.sort).to eq(document["paths"].keys.grep(%r{\A/api/v1/projects}).sort)
  end

  it "documents the ten endpoints" do
    expect(document["paths"].keys.grep(%r{\A/api/v1/projects})).to contain_exactly(
      "/api/v1/projects", "/api/v1/projects/{project_slug}", "/api/v1/projects/{project_slug}/builds",
      "/api/v1/projects/{project_slug}/builds/{id}", "/api/v1/projects/{project_slug}/tests",
      "/api/v1/projects/{project_slug}/tests/{id}", "/api/v1/projects/{project_slug}/errors",
      "/api/v1/projects/{project_slug}/errors/{id}", "/api/v1/projects/{project_slug}/flaky",
      "/api/v1/projects/{project_slug}/quarantines"
    )
  end

  it "rejects fields the document does not list" do
    schema = OpenApiHelpers.openapi.schema("Project")
    project = { "slug" => "demo", "name" => "Demo", "organization" => { "slug" => "acme", "name" => "Acme" },
                "default_branch" => "main", "latest_build" => nil, "url" => "http://www.example.com/projects/demo" }
    expect(schema.valid?(project)).to be(true)
    expect(schema.valid?(project.merge("extra" => 1))).to be(false)
    expect(schema.valid?(project.except("url"))).to be(false)
  end

  it "is served as JSON at /api/v1/openapi.json without a token" do
    get api_v1_openapi_path
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.parsed_body).to eq(document)
  end

  it "sets no cookie" do
    expect { get api_v1_openapi_path }.not_to change(Session, :count)
    expect(response.headers["Set-Cookie"]).to be_nil
  end
end
