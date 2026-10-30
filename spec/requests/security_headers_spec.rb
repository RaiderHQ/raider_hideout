require "rails_helper"

RSpec.describe "Security headers", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  it "sends a CSP with a script nonce, and puts the nonce on every script tag" do
    get root_path
    header = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    expect(header).to include("default-src 'self'", "object-src 'none'", "frame-ancestors 'none'",
                              "form-action 'self'", "base-uri 'self'")
    expect(header).to match(/script-src 'self' 'nonce-[^']+'/)
    nonce = header[/'nonce-([^']+)'/, 1]
    scripts = response.body.scan(/<script\b[^>]*>/)
    expect(scripts).not_to be_empty
    expect(scripts).to all(include(%(nonce="#{nonce}")))
  end

  it "sends a restrictive Permissions-Policy on HTML pages" do
    get root_path
    policy = response.headers["Permissions-Policy"]
    %w[camera microphone geolocation usb payment gyroscope magnetometer accelerometer].each do |feature|
      expect(policy).to include("#{feature}=()")
    end
    expect(policy).not_to include("clipboard")
  end

  it "keeps the same nonce across requests in one session (Turbo keeps the first page's policy)" do
    nonces = 2.times.map do
      get root_path
      header = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
      header[/script-src[^;]*'nonce-([^']+)'/, 1]
    end
    expect(nonces.first).to be_present
    expect(nonces.uniq.size).to eq(1)
    expect(response.body).to include(%(name="csp-nonce" content="#{nonces.first}"))
  end

  it "limits connect-src to self" do
    get root_path
    header = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    expect(header).to match(/connect-src 'self'(;|\z)/)
    expect(header).not_to include("wss:")
  end
end

RSpec.describe "Security headers when signed out", type: :request do
  before { open_signup! }

  def nonce_for(path)
    get path
    header = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    header[/script-src[^;]*'nonce-([^']*)'/, 1]
  end

  it "gives sign-in, sign-up and password-reset pages a real nonce, stable across them" do
    nonces = [ new_session_path, new_registration_path, new_password_path ].map { |path| nonce_for(path) }
    expect(nonces).to all(be_present)
    expect(nonces.uniq.size).to eq(1)
    expect(response.body).to include(%(name="csp-nonce" content="#{nonces.first}"))
  end

  def csp_directive(name)
    header = response.headers["Content-Security-Policy-Report-Only"] || response.headers["Content-Security-Policy"]
    header[/(?:\A|; )(#{name} [^;]*)/, 1].to_s
  end

  it "allows the R2 origin for images and media only, when attachments live in R2" do
    stub_const("ENV", ENV.to_h.merge("ACTIVE_STORAGE_SERVICE" => "r2", "R2_ENDPOINT" => "https://acct.r2.cloudflarestorage.com/"))
    get root_path
    expect(csp_directive("img-src")).to include("https://acct.r2.cloudflarestorage.com")
    expect(csp_directive("media-src")).to include("https://acct.r2.cloudflarestorage.com")
    %w[script-src style-src connect-src default-src].each do |name|
      expect(csp_directive(name)).not_to include("r2.cloudflarestorage.com")
    end
  end

  it "lists no storage origin when attachments stay on disk" do
    get root_path
    expect(csp_directive("img-src")).to eq("img-src 'self' data: blob:")
  end
end
