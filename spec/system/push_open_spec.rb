require "rails_helper"

RSpec.describe "Opening a push", type: :system do
  let(:user) { create(:user) }
  let(:project) { create(:project, owner: user, name: "Checkout") }
  let(:build) { create(:build, project: project, branch: "main", status: "failed", failed_count: 1) }
  let(:run) { create(:run, project: project, build: build) }

  it "signs in, then lands on the build page with the pushed card open and in view" do
    25.times do |i|
      create(:test_result, run: run, status: "passed", test_case: create(:test_case, project: project, file_path: "spec/a#{i}_spec.rb"))
    end
    failed = create(:test_result, run: run, status: "failed",
                    test_case: create(:test_case, project: project, full_name: "Zebra checkout", file_path: "spec/z_spec.rb"))
    path = Push::Payload.for(build, %w[failed])[:path]

    # The fragment never reaches the server; ?result= alone must carry the card through sign-in.
    visit path.sub(/#.*/, "")
    expect(page).to have_current_path(/\/session\/new/)
    fill_in "Email", with: user.email_address
    fill_in "Password", with: "password123"
    click_on "Sign in"

    expect(page).to have_current_path(/\A#{Regexp.escape(project_build_path(project, build))}\?result=#{failed.id}/)
    expect(page).to have_css("#test_result_#{failed.id}[open]")
    top = nil
    20.times do
      top = page.evaluate_script("document.getElementById('test_result_#{failed.id}').getBoundingClientRect().top")
      break if top >= 0 && top < page.evaluate_script("window.innerHeight")
      sleep 0.1
    end
    expect(top).to be_between(0, page.evaluate_script("window.innerHeight"))
  end
end
