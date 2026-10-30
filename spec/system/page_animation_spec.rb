require "rails_helper"

RSpec.describe "Page enter animation", type: :system do
  before { open_signup! }

  def main_animation_duration
    page.evaluate_script("getComputedStyle(document.querySelector('main')).animationDuration")
  end

  it "is neutralised in system specs, including after Turbo navigation" do
    visit new_session_path
    expect(main_animation_duration).to eq("0s")
    click_on "Create an account"
    expect(page).to have_field("Confirm password")
    expect(main_animation_duration).to eq("0s")
  end
end
