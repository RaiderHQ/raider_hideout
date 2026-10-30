require "rails_helper"

RSpec.describe "Personal tokens", type: :system do
  let(:user) { create(:user) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  it "creates a token, shows it once with the snippets, and revokes it" do
    sign_in_as(user)
    within("nav") { click_on "Tokens" }

    fill_in "Name", with: "Claude on my laptop"
    select "Never", from: "Expires"
    click_on "Create token"

    expect(page).to have_content("Copy this token now. You won't see it again.")
    plain = find("[data-testid=personal-token]").text
    expect(plain).to match(/\Ardp_[1-9A-HJ-NP-Za-km-z]{32}\z/)
    expect(page).to have_content(%(/mcp --header "Authorization: Bearer #{plain}"))
    expect(page).to have_content(%(curl -H "Authorization: Bearer #{plain}"))
    token = user.personal_tokens.sole
    expect(PersonalToken.authenticate(plain)).to eq(token)

    click_on "Back to tokens"
    expect(page).not_to have_content(plain)
    within("#personal_token_#{token.id}") do
      expect(page).to have_content("Claude on my laptop")
      expect(page).to have_css("[data-testid=token-status]", text: "active")
      accept_confirm { click_on "Revoke" }
    end

    expect(page).to have_content("Token revoked.")
    expect(page).to have_css("#personal_token_#{token.id} [data-testid=token-status]", text: "revoked")
    expect(PersonalToken.authenticate(plain)).to be_nil
  end
end
