# The signed-in person's account page: organizations, tokens, phone notifications and sign out.
# In the Raider app it also shows the server and a link the app opens as its native server screen.
class AccountsController < ApplicationController
  def show
    @organizations = helpers.menu_organizations
  end

  # The app routes this path to its native server address screen; browsers get a plain page.
  def server; end
end
