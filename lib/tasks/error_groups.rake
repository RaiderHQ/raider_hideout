namespace :raider do
  desc "Group failed test results recorded before failure clustering into error groups"
  task backfill_error_groups: :environment do
    created, linked = ErrorGroup.backfill!
    puts "Error groups created: #{created}; results linked: #{linked}"
  end
end
