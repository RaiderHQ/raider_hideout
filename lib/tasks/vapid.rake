namespace :hideout do
  namespace :vapid do
    desc "Replace the VAPID key pair; every phone must turn on notifications again"
    task rotate: :environment do
      if VapidKey.env_pair?
        abort "The VAPID keys come from #{VapidKey::PUBLIC_ENV} and #{VapidKey::PRIVATE_ENV}. " \
              "Change them there; nothing was rotated or deleted."
      end
      deleted = VapidKey.rotate!
      puts "Rotated the VAPID keys. #{deleted} devices must turn on phone notifications again."
    end
  end
end
