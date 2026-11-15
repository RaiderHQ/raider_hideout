require "rails_helper"

RSpec.describe "Native path configuration", type: :request do
  let(:expected_rules) do
    [
      [ [ ".*" ], { "context" => "default", "pull_to_refresh_enabled" => true } ],
      [ [ "/new$", "/edit$" ], { "context" => "modal", "pull_to_refresh_enabled" => false } ],
      [ [ "/session/new$" ], { "context" => "modal", "modal_dismiss_gesture_enabled" => false, "pull_to_refresh_enabled" => false } ],
      [ [ "/passwords/new$", "/passwords/edit" ], { "context" => "modal", "pull_to_refresh_enabled" => false } ],
      [ [ "^/projects$", "^/$" ], { "presentation" => "clear_all" } ],
      [ [ "/test_results/\\d+/trace/\\d+$" ], { "pull_to_refresh_enabled" => false } ],
      [ [ "^/attachments/\\d+" ], { "view_controller" => "attachment" } ],
      [ [ "^/account/server$" ], { "view_controller" => "server_address" } ],
      [ [ "^/letter_opener", "^/mcp$", "^/api/" ], { "presentation" => "none" } ]
    ].map { |patterns, properties| { "patterns" => patterns, "properties" => properties } }
  end

  it "serves the iOS rules without signing in, cached and without a cookie" do
    get "/configurations/ios_v1.json", headers: as_hotwire_native_ios("16_0")
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Cache-Control"]).to include("public", "max-age=300")
    expect(response.headers["Set-Cookie"]).to be_blank
    body = response.parsed_body
    expect(body.dig("settings", "hideout_app_api")).to eq(1)
    expect(body["rules"]).to eq(expected_rules)
  end

  it "serves the Android rules with pull to refresh set on every rule" do
    get "/configurations/android_v1.json"
    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body.dig("settings", "hideout_app_api")).to eq(1)
    expect(body["rules"].map { |rule| rule["patterns"] }).to eq(expected_rules.map { |rule| rule["patterns"] })
    expect(body["rules"]).to all(satisfy { |rule| [ true, false ].include?(rule.dig("properties", "pull_to_refresh_enabled")) })
    expect(body["rules"].map { |rule| rule.dig("properties", "pull_to_refresh_enabled") })
      .to eq([ true, false, false, false, true, false, false, false, false ])
    expect(body["rules"][6]["properties"]["view_controller"]).to eq("attachment")
  end

  it "has no other platforms or formats" do
    get "/configurations/windows_v1.json"
    expect(response).to have_http_status(:not_found)
    get "/configurations/ios_v1.xml"
    expect(response).to have_http_status(:not_found)
  end

  it "never blocks a project or organization page whose slug looks like a blocked path" do
    get "/configurations/ios_v1.json"
    none = response.parsed_body["rules"].select { |rule| rule.dig("properties", "presentation") == "none" }
    patterns = none.flat_map { |rule| rule["patterns"] }.map { |pattern| Regexp.new(pattern) }
    %w[/projects/mcp-server /projects/api/builds /organizations/letter_opener-team /projects/x/api].each do |path|
      expect(patterns.none? { |pattern| pattern.match?(path) }).to be(true), path
    end
    %w[/mcp /api/v1/runs /letter_opener].each do |path|
      expect(patterns.any? { |pattern| pattern.match?(path) }).to be(true), path
    end
  end
end
