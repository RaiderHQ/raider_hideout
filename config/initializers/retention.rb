# Reads the retention settings at boot so a bad value fails fast, not at 3:30am.
Rails.application.config.after_initialize { Retention.config }
