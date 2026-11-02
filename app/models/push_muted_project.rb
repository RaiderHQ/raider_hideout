# A project this user switched off for phone notifications. Visible projects are on unless muted.
class PushMutedProject < ApplicationRecord
  belongs_to :user
  belongs_to :project
end
