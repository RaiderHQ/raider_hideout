module Search
  # Escaping for LIKE patterns. Every pattern is used with ESCAPE '\', so a user's
  # % and _ match literally on SQLite and Postgres alike.
  module Like
    def self.escape(value)
      value.to_s.gsub(/[\\%_]/) { |char| "\\#{char}" }
    end
  end
end
