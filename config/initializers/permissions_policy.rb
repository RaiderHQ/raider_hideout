# Restrictive Permissions-Policy (value in lib/hideout/settings.rb).
# Rails' own permissions_policy DSL still emits the legacy Feature-Policy header, so the
# current header is set directly through the default response headers.
Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] = Hideout::PERMISSIONS_POLICY
