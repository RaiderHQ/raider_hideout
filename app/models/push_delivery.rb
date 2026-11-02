# One push to one device for one build attempt. The unique index is the dedup: the same
# build and attempt is never pushed twice to the same subscription.
class PushDelivery < ApplicationRecord
  belongs_to :push_subscription
  belongs_to :build
end
