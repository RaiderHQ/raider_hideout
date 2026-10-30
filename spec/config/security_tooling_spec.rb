require "rails_helper"

RSpec.describe "Security tooling" do
  it "turns on the RuboCop Security cops" do
    config = YAML.safe_load(Rails.root.join(".rubocop.yml").read)
    %w[Security/Open Security/Eval Security/YAMLLoad Security/MarshalLoad Security/JSONLoad
       Security/IoMethods Security/CompoundHash].each do |cop|
      expect(config.dig(cop, "Enabled")).to be(true), cop
    end
  end

  it "ships a gitleaks config and a local scan script" do
    expect(Rails.root.join(".gitleaks.toml").read).to include("[extend]", "useDefault = true")
    expect(File.executable?(Rails.root.join("bin/scan-secrets"))).to be(true)
  end

  it "approves only permissive licenses" do
    decisions = YAML.safe_load(Rails.root.join("doc/dependency_decisions.yml").read, permitted_classes: [ Symbol, Time, Date ])
    permitted = decisions.select { |decision| decision[0] == :permit }.map { |decision| decision[1] }
    expect(permitted).not_to be_empty
    expect(permitted.grep(/GPL/i)).to be_empty
  end

  it "keeps the ZAP rules file in the format the baseline action reads" do
    lines = Rails.root.join(".zap/rules.tsv").readlines(chomp: true).reject { |line| line.empty? || line.start_with?("#") }
    expect(lines).to all(match(/\A\d+\t(IGNORE|WARN|FAIL)\t.+\z/))
  end
end
