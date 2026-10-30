namespace :retention do
  desc "Purge attachments and test results past their retention period"
  task run: :environment do
    puts "Purged: #{Retention::Purge.new.call(dry_run: false)}"
  end

  desc "Print what retention:run would purge, without changing anything (orphan counts exclude error groups and test cases orphaned by this run's deletions)"
  task dry_run: :environment do
    puts "Would purge: #{Retention::Purge.new.call(dry_run: true)}"
  end
end
