module RaiderMcp
  module Tools
    # The shared call path (spec §6): read through the Reader as the token's user, then summarize
    # what Result keeps after cutting. Unknown projects and records and bad arguments become
    # isError results, never HTTP errors; anything unexpected is logged with the token id (never
    # the token) and answered generically.
    class Base < MCP::Tool
      READ_ONLY = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze
      PROJECT = { type: "string", description: "The project's slug, from list_projects" }.freeze
      PAGE = { type: "integer", minimum: 1, description: "Page number, from 1 (default 50 results a page)" }.freeze
      PER_PAGE = { type: "integer", # the range is checked by the Reader, so REST and MCP give one message
                   description: "Results a page, 1 to 100 (default 50); ask for fewer when a page is cut to fit" }.freeze
      LIST_LIMIT = Api::V1::Public::Reader::MAX_PER_PAGE
      INTERNAL_ERROR = "Internal error; try again.".freeze

      class << self
        def call(server_context:, **arguments)
          reader = Api::V1::Public::Reader.new(user: server_context[:user], base_url: server_context[:base_url])
          payload = read(reader, arguments)
          Result.ok(->(shown) { summary(shown, arguments) }, payload, list_key: list_key)
        rescue Api::V1::Public::Reader::NotFound, Api::V1::Public::Reader::InvalidParams => e
          Result.error(e.message)
        rescue StandardError => e
          Rails.logger.error("MCP tool #{tool_name} failed for personal token #{server_context[:token_id]}: #{e.class}: #{e.message}")
          Result.error(INTERNAL_ERROR)
        end

        # The payload key of the list Result may cut; nil for tools without one.
        def list_key = nil

        private

        def percent(rate) = rate.nil? ? "" : " #{rate}%"

        def plural(count, noun) = "#{count} #{noun.pluralize(count)}"

        def date(iso_time) = iso_time.to_s[0, 10]

        def first_line(text, limit = 80) = text.to_s.strip.lines.first.to_s.strip.truncate(limit)
      end
    end
  end
end
