require "rails_helper"

RSpec.describe "Account", type: :system do
  let(:organization) { create(:organization, name: "Acme") }
  let(:user) { create(:user).tap { |u| create(:membership, organization: organization, user: u, role: "owner") } }

  def sign_in_as(user)
    visit new_session_path
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"
    expect(page).to have_current_path(root_path)
  end

  it "opens from the Account menu in a browser" do
    sign_in_as(user)
    find("#account-menu summary").click
    within("#account-menu") { click_on "Account" }
    expect(page).to have_current_path(account_path)
    expect(page).to have_link("Tokens")
    expect(page).to have_link("Phone notifications")
    expect(page).to have_button("Sign out")
    expect(page).to have_link("Acme")
    expect(page).to have_no_content("Server:")
  end

  it "fits a phone in the browser" do
    sign_in_as(user)
    at_phone_width do
      visit account_path
      expect_no_horizontal_scroll
      expect_tap_targets("main a, main button")
    end
  end

  describe "in the Raider app" do
    it "hides the web nav, shows the server and fits a phone" do
      Capybara.using_driver(:hotwire_native_ios) do
      sign_in_as(user)
      at_phone_width do
        visit account_path
        expect(page).to have_css("body[data-native='ios']")
        expect(page).to have_no_css("nav.shadow-nav")
        expect(page).to have_content("Server: #{URI(current_url).host}:#{URI(current_url).port}")
        expect(page).to have_no_link("Phone notifications")
        expect(page.title).to eq("Account")
        expect_no_horizontal_scroll
        expect_tap_targets("main a, main button")
        click_on "Change server"
        expect(page).to have_content("Server address is only used by the Raider app.")
        visit project_path(create(:project, organization: organization, name: "Shop tests"))
        expect(page.title).to eq("Shop tests")
        expect(page).to have_no_css("nav.shadow-nav")
        expect_no_horizontal_scroll
      end
      end
    end
  end

  it "signs out from the account page" do
    sign_in_as(user)
    visit account_path
    click_on "Sign out"
    expect(page).to have_current_path(new_session_path)
  end
end
