require "rails_helper"

RSpec.describe "Views" do
  it "contain no inline event handlers (the CSP blocks them)" do
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].select do |file|
      File.read(file).match?(/\son[a-z]+\s*=|\bon(change|click|submit|input):/)
    end
    expect(offenders).to be_empty
  end

  it "wires auto-submit on the four filter selects" do
    %w[test_cases/show builds/index flaky_tests/index errors/index].each do |view|
      expect(Rails.root.join("app/views/#{view}.html.erb").read).to include('controller: "auto-submit"')
    end
  end
end
