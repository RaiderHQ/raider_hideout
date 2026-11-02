namespace :hideout do
  namespace :vapid do
    desc "Replace the VAPID key pair; every phone must turn on notifications again"
    task rotate: :environment do
      deleted = VapidKey.rotate!
      puts "Rotated the VAPID keys. #{deleted} devices must turn on phone notifications again."
    end
  end
end
