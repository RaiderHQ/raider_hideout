require "rails_helper"

RSpec.describe StackTraceHelper, type: :helper do
  describe "#parse_frame" do
    it "parses file and line, with or without a method suffix" do
      expect(helper.parse_frame("spec/a_spec.rb:12:in 'x'")).to eq(file: "spec/a_spec.rb", line: 12)
      expect(helper.parse_frame("spec/a_spec.rb:12")).to eq(file: "spec/a_spec.rb", line: 12)
    end

    it "keeps a Windows drive letter in the file" do
      expect(helper.parse_frame("C:/proj/spec/a_spec.rb:12:in 'x'")).to eq(file: "C:/proj/spec/a_spec.rb", line: 12)
    end

    it "returns nil for unparseable input" do
      expect(helper.parse_frame("not a frame")).to be_nil
      expect(helper.parse_frame(nil)).to be_nil
    end
  end

  describe "#parse_frame line terminators" do
    it "strips one trailing CR" do
      expect(helper.parse_frame("spec/a.rb:12:in 'x'\r")).to eq(file: "spec/a.rb", line: 12)
    end

    [ "\r\r", "\n", "\u2028", "\u2029" ].each do |term|
      it "is nil with #{term.inspect} inside" do
        expect(helper.parse_frame("spec/a.rb:12:in 'x'#{term}")).to be_nil
        expect(helper.parse_frame("spec/a.rb:12:in 'x'#{term}y")).to be_nil
      end
    end
  end

  describe "#project_frame?" do
    it "treats (eval) and -e frames as other" do
      expect(helper.project_frame?("(eval):1", nil)).to be(false)
      expect(helper.project_frame?("-e:1:in 'x'", nil)).to be(false)
    end

    it "accepts relative frames" do
      expect(helper.project_frame?("spec/a_spec.rb:12:in 'x'", nil)).to be(true)
      expect(helper.project_frame?("./spec/a_spec.rb:12", nil)).to be(true)
    end

    it "rejects gem, vendor, bundle, internal, absolute and Windows frames" do
      [ "vendor/bundle/x.rb:1", ".bundle/x.rb:1", "<internal:kernel>:187:in 'tap'", "/usr/lib/ruby/x.rb:1",
        "lib/gems/x/y.rb:3", "C:/proj/spec/a_spec.rb:12:in 'x'", "garbage" ].each do |line|
        expect(helper.project_frame?(line, nil)).to be(false), line
      end
    end

    it "accepts any frame in the app_frame file" do
      expect(helper.project_frame?("/abs/spec/a_spec.rb:20:in 'y'", "/abs/spec/a_spec.rb:12:in 'x'")).to be(true)
      expect(helper.project_frame?("C:/proj/spec/a_spec.rb:12:in 'x'", "C:/proj/spec/a_spec.rb:12")).to be(true)
    end
  end

  describe "#fold_frames" do
    it "keeps project lines and folds each run of other lines" do
      lines = [ "/gems/a.rb:1", "/gems/b.rb:2", "spec/a_spec.rb:3", "/gems/c.rb:4", "spec/b_spec.rb:5" ]
      expect(helper.fold_frames(lines, nil)).to eq([
        { kind: :folded, lines: [ "/gems/a.rb:1", "/gems/b.rb:2" ] },
        { kind: :project, text: "spec/a_spec.rb:3" },
        { kind: :folded, lines: [ "/gems/c.rb:4" ] },
        { kind: :project, text: "spec/b_spec.rb:5" }
      ])
    end

    it "folds an all-gem trace into one segment and an empty trace into none" do
      expect(helper.fold_frames(Array.new(7) { "/gems/x.rb:#{_1 + 1}" }, nil).map { _1[:kind] }).to eq([ :folded ])
      expect(helper.fold_frames([], nil)).to eq([])
    end
  end

  describe "#failure_location" do
    it "shows file:line only" do
      expect(helper.failure_location("spec/a_spec.rb:12:in 'x'")).to eq("spec/a_spec.rb:12")
      expect(helper.failure_location(nil)).to be_nil
    end
  end
end
