require "rails_helper"
require "rake"

RSpec.describe "retention rake tasks" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.none? { |t| t.name == "retention:run" } }

  let(:report) { Retention::Report.new(runs: 2, results: 5, attachments: 1, error_groups: 0, test_cases: 1) }
  let(:purge) { instance_double(Retention::Purge) }

  before { allow(Retention::Purge).to receive(:new).and_return(purge) }

  it "retention:run purges and prints the report" do
    allow(purge).to receive(:call).with(dry_run: false).and_return(report)
    task = Rake::Task["retention:run"]
    task.reenable
    expect { task.invoke }.to output("Purged: runs=2 results=5 attachments=1 error_groups=0 test_cases=1\n").to_stdout
  end

  it "retention:dry_run prints what would be purged" do
    allow(purge).to receive(:call).with(dry_run: true).and_return(report)
    task = Rake::Task["retention:dry_run"]
    task.reenable
    expect { task.invoke }.to output("Would purge: runs=2 results=5 attachments=1 error_groups=0 test_cases=1\n").to_stdout
  end

  it "schedules retention after the backup in production" do
    production = YAML.load(ERB.new(Rails.root.join("config/recurring.yml").read).result, aliases: true).fetch("production")
    expect(production.fetch("retention")).to include("class" => "RetentionJob", "schedule" => "at 3:30am every day")
  end
end
