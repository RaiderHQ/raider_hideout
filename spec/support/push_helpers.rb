module PushHelpers
  def b64url(bytes) = Base64.urlsafe_encode64(bytes.pack("C*"), padding: false)

  REAL_P256DH_BYTES = OpenSSL::PKey::EC.generate("prime256v1").public_key.to_bn.to_s(2).bytes.freeze

  # A genuine point on prime256v1; the model rejects bytes that are not on the curve.
  REAL_P256DH = Base64.urlsafe_encode64(REAL_P256DH_BYTES.pack("C*"), padding: false).freeze

  def valid_p256dh = REAL_P256DH

  def valid_auth = b64url(Array.new(16) { |i| i + 1 })

  def fcm_endpoint(suffix = "abc123") = "https://fcm.googleapis.com/fcm/send/#{suffix}"
end

RSpec.configure { |c| c.include PushHelpers, type: :request; c.include PushHelpers, type: :model; c.include PushHelpers, type: :system }
