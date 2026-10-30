require "rails_helper"

RSpec.describe "Personal tokens", type: :request do
  let(:user) { create(:user) }

  before { sign_in(user) }

  def page_html = Nokogiri::HTML(response.body)

  it "lists only the user's own tokens with prefix, dates, expiry and status" do
    active, = PersonalToken.issue!(user: user, name: "Laptop", expires_in_days: 90)
    forever, = PersonalToken.issue!(user: user, name: "CI box", expires_in_days: nil)
    revoked, = PersonalToken.issue!(user: user, name: "Old", expires_in_days: 30)
    revoked.revoke!
    PersonalToken.issue!(user: create(:user), name: "Someone else's", expires_in_days: 90)

    get personal_tokens_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Laptop", "CI box", "Old", "#{active.token_prefix}…")
    expect(response.body).not_to include("Someone else")
    forever_row = page_html.at_css("#personal_token_#{forever.id}")
    expect(forever_row.css("td").map { _1.text.squish }).to include("never", "active")
    expect(forever_row.at_css("button")&.text).to eq("Revoke")
    revoked_row = page_html.at_css("#personal_token_#{revoked.id}")
    expect(revoked_row.at_css("[data-testid=token-status]").text.squish).to eq("revoked")
    expect(revoked_row.at_css("button")).to be_nil
  end

  it "offers a create form with a name and an expiry select defaulting to 90 days, posted without Turbo" do
    get personal_tokens_path

    form = page_html.at_css("form[action='/account/tokens']")
    expect(form["data-turbo"]).to eq("false")
    expect(form.at_css("input[name='personal_token[name]']")).to be_present
    select = form.at_css("select[name='personal_token[expires_in]']")
    expect(select.css("option").map { [ _1.text, _1["value"] ] })
      .to eq([ [ "30 days", "30" ], [ "90 days", "90" ], [ "365 days", "365" ], [ "Never", "never" ] ])
    expect(select.at_css("option[selected]")["value"]).to eq("90")
  end

  it "creates a token and shows it once, with the MCP and curl snippets" do
    post personal_tokens_path, params: { personal_token: { name: "Claude", expires_in: "30" } }

    expect(response).to have_http_status(:ok)
    plain = response.body[/rdp_[1-9A-HJ-NP-Za-km-z]{32}/]
    expect(plain).to be_present
    expect(page_html.at_css("[data-testid=personal-token]").text).to eq(plain)
    expect(response.body).to include("Copy this token now. You won't see it again.")
    expect(response.body).to include(%(claude mcp add --transport http raider http://www.example.com/mcp --header "Authorization: Bearer #{plain}"))
    expect(response.body).to include(%(curl -H "Authorization: Bearer #{plain}" http://www.example.com/api/v1/projects))
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.body).to match(%r{<head>.*<meta name="turbo-cache-control" content="no-cache">.*</head>}m)

    token = user.personal_tokens.sole
    expect(token).to have_attributes(name: "Claude", token_prefix: plain.first(8))
    expect(token.expires_at).to be_within(1.minute).of(30.days.from_now)

    get personal_tokens_path
    expect(response.body).not_to include(plain)
  end

  it "creates a token that never expires" do
    post personal_tokens_path, params: { personal_token: { name: "Forever", expires_in: "never" } }
    expect(response).to have_http_status(:ok)
    expect(user.personal_tokens.sole.expires_at).to be_nil
  end

  it "re-renders the page with the errors and 422 for invalid input" do
    PersonalToken.issue!(user: user, name: "Laptop", expires_in_days: 90)
    {
      { name: " ", expires_in: "90" } => "Name can&#39;t be blank",
      { name: "Phone", expires_in: "30.0" } => "Expiry must be 30, 90 or 365 days, or never",
      { name: "Phone", expires_in: "7" } => "Expiry must be 30, 90 or 365 days, or never",
      { name: "Laptop", expires_in: "90" } => "Name is already used by one of your active tokens"
    }.each do |attrs, message|
      post personal_tokens_path, params: { personal_token: attrs }
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(message)
      expect(page_html.at_css("form[action='/account/tokens']")).to be_present
    end
    expect(user.personal_tokens.count).to eq(1)
  end

  it "keeps the chosen expiry when it re-renders" do
    post personal_tokens_path, params: { personal_token: { name: " ", expires_in: "365" } }
    expect(page_html.at_css("select[name='personal_token[expires_in]'] option[selected]")["value"]).to eq("365")
  end

  it "revokes a token without deleting it" do
    token, plain = PersonalToken.issue!(user: user, name: "Laptop", expires_in_days: 90)

    delete personal_token_path(token)

    expect(response).to redirect_to(personal_tokens_path)
    expect(flash[:notice]).to eq("Token revoked.")
    expect(token.reload.status).to eq("revoked")
    expect(PersonalToken.authenticate(plain)).to be_nil
  end

  it "asks for confirmation before revoking" do
    PersonalToken.issue!(user: user, name: "Laptop", expires_in_days: 90)
    get personal_tokens_path
    expect(page_html.at_css("form[data-turbo-confirm] button")&.text).to eq("Revoke")
  end

  it "404s on another user's token and leaves it active" do
    theirs, = PersonalToken.issue!(user: create(:user), name: "Theirs", expires_in_days: 90)

    delete personal_token_path(theirs)

    expect(response).to have_http_status(:not_found)
    expect(theirs.reload.revoked_at).to be_nil
  end

  it "links to the page from the navbar" do
    get root_path
    expect(page_html.at_css("nav a[href='/account/tokens']")&.text).to eq("Tokens")
  end

  it "requires sign-in" do
    delete session_path
    get personal_tokens_path
    expect(response).to redirect_to(new_session_path)
  end
end
