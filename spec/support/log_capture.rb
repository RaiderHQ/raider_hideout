module LogCapture
  # Returns what Rails logged while the block ran.
  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    old = Rails.logger
    Rails.logger = logger
    ActionController::Base.logger = logger
    yield
    io.string
  ensure
    Rails.logger = old
    ActionController::Base.logger = old
  end
end

RSpec.configure { |c| c.include LogCapture, type: :request }
