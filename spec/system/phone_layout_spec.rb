require "rails_helper"

RSpec.describe "Phone layout", type: :system do
  let(:user) { create(:user) }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  [ 360, 430 ].each do |width|
    it "nav fits a phone at #{width}px" do
      sign_in_as(user)

      at_phone_width(width) do
        visit root_path
        expect_no_horizontal_scroll
        find("#account-menu summary").click
        expect_tap_targets("#account-menu summary, #account-menu a, #account-menu button")
        expect_no_horizontal_scroll
        click_on "Sign out"
        expect(page).to have_current_path(new_session_path)
      end
    end
  end

  it "keeps Tokens reachable in the account menu at desktop width" do
    sign_in_as(user)
    find("#account-menu summary").click
    within("#account-menu") { click_on "Tokens" }
    expect(page).to have_current_path(personal_tokens_path)
  end
end
