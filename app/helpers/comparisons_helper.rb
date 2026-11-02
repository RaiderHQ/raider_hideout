module ComparisonsHelper
  ComparisonBlock = Data.define(:name, :status, :entry, :images)

  KINDS = %w[expected actual diff].freeze
  IMAGE_NAME = %r{\Acomparison:([A-Za-z0-9_/-]+):(expected|actual|diff)\z}

  def comparison_attachment?(result, attachment)
    result.attachment_name(attachment).start_with?("comparison:")
  end

  def comparison_blocks(result)
    return [] unless TestResult::FAILING_STATUSES.include?(result.status)

    by_name = Hash.new { |h, k| h[k] = {} }
    result.attachments.sort_by { |a| [ a.created_at, a.id ] }.each do |attachment|
      match = IMAGE_NAME.match(result.attachment_name(attachment))
      by_name[match[1]][match[2]] = attachment if match
    end

    entries = Array(result.comparisons)
    blocks = entries.map do |entry|
      images = by_name[entry["name"]]
      ComparisonBlock.new(name: entry["name"], status: entry["status"], entry: entry, images: KINDS.select { |k| images.key?(k) }.to_h { |k| [ k, images[k] ] })
    end
    known = entries.map { |e| e["name"] }
    by_name.each do |name, images|
      next if known.include?(name)
      blocks << ComparisonBlock.new(name: name, status: nil, entry: nil, images: KINDS.select { |k| images.key?(k) }.to_h { |k| [ k, images[k] ] })
    end
    blocks
  end

  def comparison_numbers(entry)
    pixels, ratio = entry["diff_pixels"], entry["diff_ratio"]
    pixel_text = "#{number_with_delimiter(pixels)} #{pixels == 1 ? 'pixel' : 'pixels'}" if pixels
    ratio_text = number_to_percentage(ratio * 100, precision: 2) if ratio
    return nil unless pixel_text || ratio_text
    text = [ pixel_text, ("(#{ratio_text})" if pixel_text && ratio_text) || ratio_text ].compact.join(" ")
    "#{text} differ"
  end

  def comparison_allowance(entry)
    allowed = if entry["max_diff_ratio"]
      number_to_percentage(entry["max_diff_ratio"] * 100, precision: 2)
    elsif entry["max_diff_pixels"]
      "#{number_with_delimiter(entry['max_diff_pixels'])} #{entry['max_diff_pixels'] == 1 ? 'pixel' : 'pixels'}"
    end
    parts = [ allowed, ("threshold #{entry['threshold']}" if entry["threshold"]) ].compact
    "Allowed: #{parts.join(', ')}" if parts.any?
  end

  def comparison_size_change(entry)
    expected, actual = entry["expected_size"], entry["actual_size"]
    return nil unless expected && actual && expected != actual
    "Size changed: #{expected.join('×')} → #{actual.join('×')}"
  end

  def comparison_default_kind(block)
    %w[diff actual expected].find { |k| block.images.key?(k) }
  end
end
