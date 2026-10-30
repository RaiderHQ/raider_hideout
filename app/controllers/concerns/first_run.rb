# While no user exists, HTML pages send the visitor to /setup (spec 2026-10-29 §5.3).
module FirstRun
  extend ActiveSupport::Concern

  included do
    prepend_before_action :redirect_to_setup
  end

  # Cached once true: after the first user, no request pays for the query again.
  def self.completed?
    @completed ||= User.exists?
  end

  def self.reset! = @completed = nil

  private

  def redirect_to_setup
    return unless Rails.configuration.x.first_run_redirect && request.format.html?
    return if FirstRun.completed?

    redirect_to setup_path
  end
end
