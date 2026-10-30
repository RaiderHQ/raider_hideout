require "rails_helper"

RSpec.describe "Licenses" do
  permissive = %w[MIT Apache-2.0 BSD-2-Clause BSD-3-Clause ISC Ruby]

  it "ships the Apache-2.0 license and the NOTICE" do
    expect(Rails.root.join("LICENSE").read).to include("Apache License", "Version 2.0, January 2004")
    expect(Rails.root.join("NOTICE").read).to eq("Raider Hideout\nCopyright 2026 Augustin Gottlieb and contributors\n")
  end

  # A dual-licensed gem passes when one of its options is permissive (rdoc is Ruby/GPL-2.0-only).
  it "has no runtime gem without a permissive license option" do
    definition = Bundler.definition
    left_out = Bundler.settings[:without].map(&:to_sym)
    runtime = definition.specs_for(definition.groups - %i[development test] - left_out)
    offenders = runtime.filter_map do |spec|
      installed = Gem::Specification.find_all_by_name(spec.name, spec.version.to_s).first
      next unless installed

      licenses = installed.licenses
      "#{spec.name} (#{licenses.join('/').presence || 'no license'})" if (licenses & permissive).empty?
    end
    expect(offenders).to be_empty
  end
end
