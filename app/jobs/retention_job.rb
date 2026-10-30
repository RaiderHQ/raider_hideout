class RetentionJob < ApplicationJob
  queue_as :default

  def perform
    report = Retention::Purge.new.call
    Rails.logger.info("[retention] #{report}")
  end
end
