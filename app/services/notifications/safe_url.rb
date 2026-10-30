module Notifications
  module SafeUrl
    MAX_LENGTH = 3000

    def self.valid?(url)
      return false if url.blank? || url.length > MAX_LENGTH

      %w[http https].include?(URI.parse(url).scheme)
    rescue URI::InvalidURIError
      false
    end
  end
end
