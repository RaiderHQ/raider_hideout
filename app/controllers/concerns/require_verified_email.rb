# Signed-in users with an unverified address only reach the check-inbox page,
# sign-out and password reset until they click the emailed link.
module RequireVerifiedEmail
  extend ActiveSupport::Concern

  included do
    before_action :require_verified_email
  end

  class_methods do
    def allow_unverified_access(**options)
      skip_before_action :require_verified_email, **options
    end
  end

  private

  def require_verified_email
    return unless authenticated? && Current.user&.verified? == false

    # Remember where a GET was heading so verifying can take the user back.
    session[:return_to_after_verification] = request.fullpath if request.get? || request.head?
    redirect_to verify_email_path
  end
end
