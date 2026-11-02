require "rails_helper"

RSpec.describe ComparisonsHelper, type: :helper do
  let(:entry) do
    { "name" => "home", "status" => "failed", "diff_pixels" => 1_797_705, "diff_ratio" => 0.9992579375667022, "threshold" => 0.2,
      "max_diff_pixels" => 0, "max_diff_ratio" => nil, "expected_size" => [ 1920, 937 ], "actual_size" => [ 1920, 937 ] }
  end

  it "formats numbers" do
    expect(helper.comparison_numbers(entry)).to eq("1,797,705 pixels (99.93%) differ")
    expect(helper.comparison_numbers(entry.merge("diff_ratio" => nil))).to eq("1,797,705 pixels differ")
    expect(helper.comparison_numbers(entry.merge("diff_pixels" => nil))).to eq("99.93% differ")
    expect(helper.comparison_numbers(entry.merge("diff_pixels" => nil, "diff_ratio" => nil))).to be_nil
  end

  it "formats the allowance" do
    expect(helper.comparison_allowance(entry)).to eq("Allowed: 0 pixels, threshold 0.2")
    expect(helper.comparison_allowance(entry.merge("max_diff_ratio" => 0.005))).to eq("Allowed: 0.50%, threshold 0.2")
    expect(helper.comparison_allowance(entry.merge("max_diff_pixels" => nil, "threshold" => nil))).to be_nil
  end

  it "formats a size change only when both sizes are present and differ" do
    expect(helper.comparison_size_change(entry)).to be_nil
    expect(helper.comparison_size_change(entry.merge("actual_size" => [ 1280, 720 ]))).to eq("Size changed: 1920×937 → 1280×720")
    expect(helper.comparison_size_change(entry.merge("actual_size" => nil))).to be_nil
  end

  describe "blocks" do
    let(:result) { create(:test_result, status: "failed", comparisons: [ entry ]) }

    def attach(name, content = "x")
      result.attachments.attach(io: StringIO.new(content), filename: "#{name.tr(':', '-')}.png", content_type: "image/png", metadata: { "name" => name })
    end

    it "takes the last attachment of a name" do
      attach("comparison:home:diff", "one")
      attach("comparison:home:diff", "two")
      result.reload
      block = helper.comparison_blocks(result).first
      expect(block.images.keys).to eq(%w[diff])
      expect(block.images["diff"]).to eq(result.attachments.max_by { |a| [ a.created_at, a.id ] })
    end

    it "yields a block with nil status for an images-only name" do
      attach("comparison:other:actual")
      blocks = helper.comparison_blocks(result.reload)
      expect(blocks.map(&:name)).to eq(%w[home other])
      expect(blocks.last.status).to be_nil
      expect(blocks.last.entry).to be_nil
    end

    it "has empty images when attachments are absent" do
      expect(helper.comparison_blocks(result).first.images).to eq({})
    end

    it "orders images expected, actual, diff" do
      attach("comparison:home:diff")
      attach("comparison:home:expected")
      expect(helper.comparison_blocks(result.reload).first.images.keys).to eq(%w[expected diff])
    end

    it "identifies comparison attachments" do
      attach("comparison:home:diff")
      expect(helper.comparison_attachment?(result, result.reload.attachments.first)).to be true
    end
  end
end
