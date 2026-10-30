module Search
  # One search over a project's tests or results, read from the query box (Filter.parse)
  # or the fields form (Filter.from_params) and printed back as a canonical query
  # string (#to_query). Spec §4.1. No database access.
  class Filter
    LEVELS = %w[tests results].freeze
    STATUSES = %w[passed failed skipped pending quarantined].freeze
    RANGES = { "24h" => 24.hours, "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }.freeze
    DEFAULT_RANGE = "7d".freeze
    SORTS = %w[failures recent duration name].freeze
    MAX_QUERY = 500
    MAX_TERMS = 10
    MAX_VALUE = 100
    FIELDS = %i[text name file error statuses branch tags flaky quarantined since sort].freeze

    # key:"quoted value" | key:value | "quoted phrase" | word. A quote left open runs to the
    # end. A key is letters followed by a single colon, so Net::ReadTimeout stays a word.
    TOKEN = /([A-Za-z]+):(?!:)"([^"]*)"?|([A-Za-z]+):(?!:)(\S*)|"([^"]*)"?|(\S+)/
    KEY_LIKE = /\A[A-Za-z]+:(?!:)/

    attr_reader(*FIELDS, :notices)

    def self.parse(query)
      new.tap { |filter| filter.send(:read_query, query.to_s) }
    end

    def self.from_params(params, default_branch: nil, level: "tests")
      new.tap { |filter| filter.send(:read_params, params.to_h.stringify_keys, default_branch, level) }
    end

    def initialize(text: [], name: nil, file: nil, error: nil, statuses: [], branch: nil, tags: [], flaky: false,
                   quarantined: false, since: DEFAULT_RANGE, sort: nil)
      @text = text.dup
      @name = name
      @file = file
      @error = error
      @statuses = statuses.dup
      @branch = branch
      @tags = tags.dup
      @flaky = flaky
      @quarantined = quarantined
      @since = since
      @sort = sort
      @notices = []
    end

    def to_h = FIELDS.index_with { |field| public_send(field) }

    def ==(other) = other.is_a?(Filter) && to_h == other.to_h
    alias eql? ==

    def hash = to_h.hash

    def narrowed? = text.any? || statuses.any? || tags.any? || flaky || quarantined || [ name, file, error ].any?

    def range_start(now = Time.current) = now - RANGES.fetch(since)

    # One row per result has no failure count, so Results fall back to most recent.
    def sort_for(level)
      default = level == "results" ? "recent" : "failures"
      return default if sort.nil? || (level == "results" && sort == "failures")

      sort
    end

    def to_query
      parts = text.map { |word| quote_text(word) }
      parts << "name:#{quote(name)}" if name
      parts << "file:#{quote(file)}" if file
      parts << "error:#{quote(error)}" if error
      parts << "status:#{statuses.join(',')}" if statuses.any?
      parts << "branch:#{quote(branch)}" if branch
      tags.each { |tag| parts << "tag:#{quote(tag)}" }
      parts << "is:flaky" if flaky
      parts << "is:quarantined" if quarantined
      parts << "since:#{since}" unless since == DEFAULT_RANGE
      parts << "sort:#{sort}" if sort
      parts.join(" ")
    end

    def to_params
      { "text" => text.map { |word| quote_text(word) }.join(" "), "name" => name.to_s, "file" => file.to_s,
        "error" => error.to_s, "statuses" => statuses, "branch" => branch.to_s, "tags" => tags.join(", "),
        "flaky" => flaky ? "1" : "0", "quarantined" => quarantined ? "1" : "0", "since" => since, "sort" => sort.to_s }
    end

    private

    def read_query(query)
      if query.length > MAX_QUERY
        query = query[0, MAX_QUERY]
        @notices << "Only the first #{MAX_QUERY} characters are used"
      end
      tokens = query.scan(TOKEN)
      if tokens.size > MAX_TERMS
        tokens = tokens.first(MAX_TERMS)
        @notices << "Only the first #{MAX_TERMS} terms are used"
      end
      tokens.each do |quoted_key, quoted_value, key, value, phrase, word|
        if quoted_key then assign(quoted_key.downcase, quoted_value, %(#{quoted_key}:"#{quoted_value}"))
        elsif key then assign(key.downcase, value, "#{key}:#{value}")
        else add_text(phrase || word)
        end
      end
    end

    def read_params(params, default_branch, level)
      @text = Filter.parse(params["text"].to_s).text
      %w[name file error].each { |key| instance_variable_set(:"@#{key}", clean(params[key], key).presence) }
      @statuses = STATUSES & Array(params["statuses"]).map { |status| status.to_s.downcase }
      branch = clean(params["branch"], "branch").presence
      @branch = branch unless branch == default_branch
      @tags = split_tags(params["tags"].to_s)
      @flaky = params["flaky"].to_s == "1"
      @quarantined = params["quarantined"].to_s == "1"
      since = params["since"].to_s.downcase
      @since = RANGES.key?(since) ? since : DEFAULT_RANGE
      sort = params["sort"].to_s.downcase
      @sort = sort if SORTS.include?(sort) && sort != Filter.new.sort_for(level)
    end

    def assign(key, raw, token)
      return @notices << %(Ignored "#{token}": unknown filter) unless %w[name file error status branch tag is since sort].include?(key)

      value = clean(raw, key)
      return @notices << %(Ignored "#{token}": empty value) if value.empty?

      case key
      when "name", "file", "error", "branch" then instance_variable_set(:"@#{key}", value)
      when "status" then assign_statuses(value)
      when "tag" then split_tags(value).each { |tag| @tags << tag unless @tags.include?(tag) }
      when "is"
        if value.casecmp?("flaky") then @flaky = true
        elsif value.casecmp?("quarantined") then @quarantined = true
        else @notices << %(Ignored "#{token}": use is:flaky or is:quarantined)
        end
      when "since" then assign_choice(:since, value.downcase, RANGES.keys, token, "use 24h, 7d, 30d or 90d")
      when "sort" then assign_choice(:sort, value.downcase, SORTS, token, "use failures, recent, duration or name")
      end
    end

    def assign_statuses(value)
      given = value.downcase.split(",").map(&:strip).reject(&:empty?)
      (given - STATUSES).uniq.each { |bad| @notices << %(Ignored "status:#{bad}": unknown status) }
      good = STATUSES & given
      @statuses = good if good.any?
    end

    def assign_choice(field, value, allowed, token, hint)
      if allowed.include?(value)
        instance_variable_set(:"@#{field}", value)
      else
        @notices << %(Ignored "#{token}": #{hint})
      end
    end

    def add_text(raw)
      value = clean(raw, "text")
      @text << value unless value.empty? || @text.include?(value)
    end

    def split_tags(value)
      value.split(",").map { |tag| TestResult.normalize_tag(tag) }.reject(&:empty?).uniq
    end

    def clean(raw, key)
      value = raw.to_s.delete('"').strip
      return value if value.length <= MAX_VALUE

      notice = "Shortened #{key}: values are at most #{MAX_VALUE} characters"
      @notices << notice unless @notices.include?(notice)
      value[0, MAX_VALUE]
    end

    def quote(value) = value.match?(/\s/) ? %("#{value}") : value

    def quote_text(word) = word.match?(/\s/) || word.match?(KEY_LIKE) ? %("#{word}") : word
  end
end
