module Api
  module V1
    # Plain-Ruby presenters return Hashes for both REST and MCP (spec §5). Times are ISO 8601
    # UTC strings, so render json: and JSON.generate produce the same text.
    class BasePresenter
      def initialize(url_options:)
        @url_options = url_options
      end

      private

      def time(value)
        value&.utc&.iso8601
      end

      def clip(text, limit)
        text&.to_s&.first(limit)
      end

      # SQLite returns aggregate timestamps as strings.
      def parse_time(value)
        value.is_a?(String) ? Time.zone.parse("#{value} UTC") : value
      end

      def url(helper, *args)
        Rails.application.routes.url_helpers.public_send(helper, *args, **@url_options)
      end
    end
  end
end
