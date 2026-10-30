require "storage_service"

# Be sure to restart your server when you modify this file.
# Enforced in production; report-only in development and test.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self
    # Attachments in S3 are redirects to the bucket's origin (spec 2026-10-29 §7.2).
    policy.img_src     :self, :data, :blob, -> { StorageService.s3_origin }
    policy.media_src   :self, :blob, -> { StorageService.s3_origin }
    policy.font_src    :self
    policy.connect_src :self
    policy.object_src  :none
    policy.frame_ancestors :none
    policy.form_action :self
    policy.base_uri    :self
  end
  # Stable per session (Rails default): Turbo Drive keeps the first page's CSP, so a per-request nonce
  # would block Chartkick's inline scripts after navigation. connect-src 'self' covers same-origin ws/wss.
  # Stable per session, so a page reached by Turbo Drive (which keeps the first
  # page's policy) still runs its nonced scripts. Kept in the session rather than
  # derived from the session id, which is blank until the session is loaded
  # (signed-out pages would otherwise get an empty, invalid nonce).
  config.content_security_policy_nonce_generator = ->(request) { request.session[:csp_nonce] ||= SecureRandom.base64(16) }
  # style-src too: Turbo's progress bar injects a <style> element carrying the csp-nonce meta value.
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
