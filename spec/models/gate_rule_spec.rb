require "rails_helper"

RSpec.describe GateRule do
  let(:project) { create(:project) }

  it "is off by default and enabled by any one rule" do
    rule = described_class.new(project: project)
    expect(rule).to have_attributes(min_pass_rate: nil, no_new_failures: false, no_new_flaky: false)
    expect(rule).not_to be_enabled
    expect(described_class.new(project: project, min_pass_rate: 98)).to be_enabled
    expect(described_class.new(project: project, no_new_failures: true)).to be_enabled
    expect(described_class.new(project: project, no_new_flaky: true)).to be_enabled
  end

  it "accepts a minimum pass rate from 1 to 100, or blank for off" do
    [ 1, 50, 100, nil, "" ].each do |value|
      rule = described_class.new(project: project, min_pass_rate: value)
      expect(rule).to be_valid, "#{value.inspect}: #{rule.errors.full_messages}"
    end
    expect(described_class.new(project: project, min_pass_rate: "").min_pass_rate).to be_nil
  end

  it "rejects 0, 101, decimals and text" do
    { 0 => "must be in 1..100", 101 => "must be in 1..100", "98.5" => "must be an integer", "abc" => "is not a number" }
      .each do |value, message|
        rule = described_class.new(project: project, min_pass_rate: value)
        expect(rule).not_to be_valid
        expect(rule.errors[:min_pass_rate]).to include(message)
      end
  end

  it "allows one rule per project" do
    create(:gate_rule, project: project)
    expect(described_class.new(project: project)).not_to be_valid
    expect { described_class.new(project: project).save(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "is deleted with its project" do
    create(:gate_rule, project: project, min_pass_rate: 90)
    project.destroy!
    expect(described_class.count).to eq(0)
  end

  it "keeps the rule when the user who changed it is deleted" do
    editor = create(:user, with_personal_organization: false)
    rule = create(:gate_rule, project: project, min_pass_rate: 90, updated_by: editor)
    User.where(id: editor.id).delete_all
    expect(rule.reload).to have_attributes(updated_by_id: nil, min_pass_rate: 90)
  end

  describe "Project#gate_enabled?" do
    it "is false without a rule or with an all-off rule, true with an enabled one" do
      expect(project).not_to be_gate_enabled
      create(:gate_rule, project: project)
      expect(project.reload).not_to be_gate_enabled
      project.gate_rule.update!(no_new_flaky: true)
      expect(project.reload).to be_gate_enabled
    end
  end
end
