module PushHelpers
  def b64url(bytes) = Base64.urlsafe_encode64(bytes.pack("C*"), padding: false)

  def valid_p256dh = b64url([ 4 ] + Array.new(64) { |i| i + 1 })

  def valid_auth = b64url(Array.new(16) { |i| i + 1 })

  def fcm_endpoint(suffix = "abc123") = "https://fcm.googleapis.com/fcm/send/#{suffix}"
end

RSpec.configure { |c| c.include PushHelpers, type: :request; c.include PushHelpers, type: :model; c.include PushHelpers, type: :system }
