module Analytics
  # The Analytics page's filter (spec 2026-10-28 §4.2): one query box in Explore syntax that
  # keeps only branch:, tag:, file: and since: (7d, 30d or 90d, default 30d). Every other term
  # is dropped with a notice. The kept terms are read by Search::Filter, so values are cleaned,
  # tags normalized and the result queries share Explore's matching rules. No database access.
  class Filter
    RANGES = %w[7d 30d 90d].freeze
    DEFAULT_RANGE = "30d".freeze
    ACCEPTED = %w[branch tag file since].freeze

    attr_reader :notices, :search

    def self.parse(query, default_branch:)
      new(default_branch: default_branch).tap { |filter| filter.send(:read, query.to_s) }
    end

    def initialize(default_branch:)
      @default_branch = default_branch
      @notices = []
      @search = Search::Filter.new(since: DEFAULT_RANGE)
    end

    def branch = search.branch || @default_branch
    def file = search.file
    def tags = search.tags
    def since = search.since
    def days = since.to_i
    def length = Search::Filter::RANGES.fetch(since)
    def range_start(now = Time.current) = search.range_start(now)

    # file: and tag: narrow the result numbers only; build numbers follow branch: and since:.
    def narrowed? = file.present? || tags.any?

    # The canonical query, shown in the box and carried into every link. `file:` replaces
    # the file term (the spec file list's links).
    def to_query(file: self.file)
      parts = []
      parts << "file:#{quote(file)}" if file
      parts << "branch:#{quote(search.branch)}" if search.branch
      tags.each { |tag| parts << "tag:#{quote(tag)}" }
      parts << "since:#{since}" unless since == DEFAULT_RANGE
      parts.join(" ")
    end

    # The same branch, tags, file and range as an Explore query, plus a sort or is:flaky.
    def explore_query(sort: nil, flaky: false)
      Search::Filter.new(file: file, branch: search.branch, tags: tags, since: since, sort: sort, flaky: flaky).to_query
    end

    private

    def read(query)
      if query.length > Search::Filter::MAX_QUERY
        query = query[0, Search::Filter::MAX_QUERY]
        @notices << "Only the first #{Search::Filter::MAX_QUERY} characters are used"
      end
      tokens = query.scan(Search::Filter::TOKEN)
      if tokens.size > Search::Filter::MAX_TERMS
        tokens = tokens.first(Search::Filter::MAX_TERMS)
        @notices << "Only the first #{Search::Filter::MAX_TERMS} terms are used"
      end
      kept = tokens.filter_map { |quoted_key, quoted_value, key, value, phrase, word| keep(quoted_key, quoted_value, key, value, phrase || word) }
      parsed = Search::Filter.parse(kept.join(" "))
      @notices.concat(parsed.notices)
      since = kept.any? { |token| token.downcase.start_with?("since:") } ? parsed.since : DEFAULT_RANGE
      @search = Search::Filter.new(file: parsed.file, branch: parsed.branch, tags: parsed.tags, since: since)
    end

    def keep(quoted_key, quoted_value, key, value, text)
      if quoted_key then accept(quoted_key, quoted_value, %(#{quoted_key}:"#{quoted_value}"))
      elsif key then accept(key, value, "#{key}:#{value}")
      else ignore(text) unless text.strip.empty?
      end
    end

    def accept(key, value, token)
      return ignore(token) unless ACCEPTED.include?(key.downcase)
      return token unless key.casecmp?("since") && !RANGES.include?(value.strip.downcase)

      @notices << %(Ignored "#{token}": use 7d, 30d or 90d)
      nil
    end

    def ignore(term)
      @notices << %(Ignored "#{term}": not an analytics filter)
      nil
    end

    def quote(value) = value.match?(/\s/) ? %("#{value}") : value
  end
end
