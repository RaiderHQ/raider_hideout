# The Hotwire Native path configuration Hideout serves to the Raider app at
# /configurations/{ios,android}_v1.json. One frozen rule list for both platforms; Android's
# pull to refresh defaults to off, so its rules carry the setting explicitly. Later rules win.
module NativePathConfiguration
  APP_API = 1
  PLATFORMS = %w[ios android].freeze

  # [patterns, iOS properties, Android pull_to_refresh_enabled]
  RULES = [
    [ [ ".*" ], { context: "default", pull_to_refresh_enabled: true }, true ],
    [ [ "/new$", "/edit$" ], { context: "modal", pull_to_refresh_enabled: false }, false ],
    [ [ "/session/new$" ], { context: "modal", modal_dismiss_gesture_enabled: false, pull_to_refresh_enabled: false }, false ],
    [ [ "/passwords/new$", "/passwords/edit" ], { context: "modal", pull_to_refresh_enabled: false }, false ],
    [ [ "^/projects$", "^/$" ], { presentation: "clear_all" }, true ],
    [ [ "/test_results/\\d+/trace/\\d+$" ], { pull_to_refresh_enabled: false }, false ],
    [ [ "^/attachments/\\d+" ], { view_controller: "attachment" }, false ],
    [ [ "^/account/server$" ], { view_controller: "server_address" }, false ],
    [ [ "/letter_opener", "/mcp", "/api/" ], { presentation: "none" }, false ]
  ].freeze

  module_function

  def as_json(platform)
    raise ArgumentError, "unknown platform" unless PLATFORMS.include?(platform)

    rules = RULES.map do |patterns, properties, android_refresh|
      properties = properties.merge(pull_to_refresh_enabled: android_refresh) if platform == "android"
      { patterns: patterns, properties: properties }
    end
    { settings: { hideout_app_api: APP_API }, rules: rules }
  end
end
