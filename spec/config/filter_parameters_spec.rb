require "rails_helper"

RSpec.describe "Parameter filtering" do
  it "filters the run payload from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    expect(filter.filter("payload" => "{}")).to eq("payload" => "[FILTERED]")
  end
end
