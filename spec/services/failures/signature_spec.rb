require "rails_helper"

RSpec.describe Failures::Signature do
  def signature(exception_class: "RuntimeError", message: "boom", app_frame: nil, backtrace: nil)
    described_class.for(exception_class: exception_class, message: message, app_frame: app_frame, backtrace: backtrace)
  end

  def message_for(message) = signature(message: message).normalized_message

  describe "exception class" do
    it "strips it" do
      expect(signature(exception_class: "  Capybara::ElementNotFound ").exception_class).to eq("Capybara::ElementNotFound")
    end

    it "is UnknownError when blank" do
      expect(signature(exception_class: nil).exception_class).to eq("UnknownError")
      expect(signature(exception_class: "  ").exception_class).to eq("UnknownError")
    end
  end

  describe "message normalization" do
    it "drops a Cucumber step prefix paragraph" do
      expect(message_for("Then I see \"x\" (features/a.feature:12)\n\nexpected 1 got 2")).to eq("expected <n> got <n>")
    end

    it "keeps a first paragraph that is not a step prefix" do
      expect(message_for("first part\n\nsecond part")).to eq("first part")
    end

    it "keeps only the first line" do
      expect(message_for("Unable to find css \"#btn\"\n\nDid you mean?\n  more")).to eq("Unable to find css \"…\"")
    end

    it "uses the first non-blank line of a message that starts with a newline" do
      expect(message_for("\nexpected: 1\n     got: 2\n\n(compared using ==)\n")).to eq("expected: <n>")
    end

    it "replaces double- and single-quoted text" do
      expect(message_for("expected \"abc\" to eq 'def'")).to eq("expected \"…\" to eq \"…\"")
    end

    it "treats an apostrophe after a word character as part of the word" do
      expect(message_for("can't find 'x'")).to eq("can't find \"…\"")
    end

    it "replaces UUIDs" do
      expect(message_for("no user 3f2b8c1e-9a4d-4e6f-8b7a-1c2d3e4f5a6b here")).to eq("no user <uuid> here")
    end

    it "replaces hex addresses" do
      expect(message_for("#<Object:0x000f1a2b3c> failed")).to eq("#<Object:<hex>> failed")
    end

    it "replaces digit runs" do
      expect(message_for("waited 30 seconds for 2 rows")).to eq("waited <n> seconds for <n> rows")
    end

    it "collapses whitespace" do
      expect(message_for("  too   many \t spaces  ")).to eq("too many spaces")
    end

    it "truncates to 200 characters" do
      expect(message_for("a" * 300)).to eq("a" * 200)
    end

    it "is empty for a nil message" do
      expect(message_for(nil)).to eq("")
      expect(signature(message: nil, backtrace: nil).digest).to match(/\A\h{64}\z/)
    end
  end

  describe "frame" do
    it "uses app_frame without its line number" do
      expect(signature(app_frame: "spec/pages/login_page.rb:42:in 'LoginPage#submit'").frame)
        .to eq("spec/pages/login_page.rb:in submit")
    end

    it "falls back to the first app line of an absolute backtrace, made relative" do
      backtrace = [ "/home/runner/.gem/ruby/4.0.0/gems/capybara-3.40/lib/capybara/node/finders.rb:10:in 'find'",
                    "/home/runner/work/x/x/spec/pages/login_page.rb:42:in 'click'" ]
      expect(signature(backtrace: backtrace).frame).to eq("spec/pages/login_page.rb:in click")
    end

    it "accepts a newline-joined backtrace" do
      backtrace = "<internal:kernel>:1:in 'loop'\n/usr/lib/ruby/4.0.0/set.rb:3:in 'x'\napp/models/user.rb:7:in 'save'"
      expect(signature(backtrace: backtrace).frame).to eq("app/models/user.rb:in save")
    end

    it "skips vendor and .bundle lines" do
      backtrace = [ "/app/vendor/bundle/x.rb:1:in 'a'", "/app/.bundle/y.rb:2:in 'b'", "/w/test/models/u_test.rb:3:in 'c'" ]
      expect(signature(backtrace: backtrace).frame).to eq("test/models/u_test.rb:in c")
    end

    it "is empty when every line is a gem or stdlib line" do
      backtrace = [ "/gems/rspec-core/lib/rspec/core.rb:1:in 'run'", "/usr/local/lib/ruby/4.0.0/timeout.rb:2:in 'x'",
                    "<internal:kernel>:3:in 'loop'" ]
      expect(signature(backtrace: backtrace).frame).to eq("")
      expect(signature(backtrace: nil).frame).to eq("")
    end

    it "normalizes Windows backslashes before matching app roots and markers" do
      expect(signature(backtrace: [ "C:\\a\\gems\\x.rb:1:in 'y'", "C:\\w\\spec\\a.rb:3:in 'x'" ]).frame)
        .to eq("spec/a.rb:in x")
      expect(signature(app_frame: "spec\\pages\\a.rb:3:in 'x'").frame).to eq("spec/pages/a.rb:in x")
    end

    it "skips an absolute fallback line with no app root" do
      backtrace = [ "/home/runner/.rbenv/versions/3.3/bin/rspec:25:in '<main>'" ]
      expect(signature(backtrace: backtrace).frame).to eq("")
      expect(signature(backtrace: backtrace + [ "/w/spec/a.rb:2:in 'x'" ]).frame).to eq("spec/a.rb:in x")
    end

    it "strips a leading ./ from app_frame" do
      expect(signature(app_frame: "./spec/a.rb:3:in 'x'").frame).to eq("spec/a.rb:in x")
      expect(signature(app_frame: "./spec/a.rb:3:in 'x'").digest).to eq(signature(app_frame: "spec/a.rb:9:in 'x'").digest)
    end

    it "does not cut a relative app_frame" do
      expect(signature(app_frame: "lib/app/x.rb:3:in 'y'").frame).to eq("lib/app/x.rb:in y")
    end

    it "cuts an absolute path at the last app root" do
      expect(signature(backtrace: [ "/x/spec/support/lib/h.rb:4:in 'z'" ]).frame).to eq("lib/h.rb:in z")
    end

    it "gives the same digest on two CI runners with different roots" do
      gitlab = signature(backtrace: [ "/builds/abc/spec/pages/login_page.rb:42:in 'click'" ])
      github = signature(backtrace: [ "/home/runner/work/app/app/spec/pages/login_page.rb:42:in 'click'" ])
      expect(gitlab.digest).to eq(github.digest)
    end
  end

  describe "frame labels across Ruby versions" do
    it "gives one digest for Ruby 3.3 and 3.4 labels" do
      a = signature(app_frame: "spec/pages/login.rb:12:in `submit'")
      b = signature(app_frame: "spec/pages/login.rb:12:in 'LoginPage#submit'")
      expect(a.frame).to eq("spec/pages/login.rb:in submit")
      expect([ b.frame, b.digest ]).to eq([ a.frame, a.digest ])
    end

    it "normalizes block labels and class methods" do
      a = signature(app_frame: "spec/p.rb:3:in `block in submit'")
      b = signature(app_frame: "spec/p.rb:3:in 'block in Admin::LoginPage#submit'")
      c = signature(app_frame: "spec/p.rb:3:in 'Admin::LoginPage.open'")
      expect(b.digest).to eq(a.digest)
      expect(a.frame).to eq("spec/p.rb:in block in submit")
      expect(c.frame).to eq("spec/p.rb:in open")
    end

    it "caps app_frame at 500 characters before normalizing" do
      frame = signature(app_frame: "spec/#{'a' * 600}.rb:1:in 'X#y'").frame
      expect(frame.length).to be <= 500
    end
  end

  describe "placeholder step prefix" do
    it "drops a leading Step paragraph" do
      expect(message_for("Step\n\nelement not found")).to eq("element not found")
    end
  end

  describe "digest" do
    it "is the SHA256 of class, message and frame" do
      result = signature(app_frame: "spec/a.rb:1:in 'x'")
      expect(result.digest).to eq(Digest::SHA256.hexdigest("RuntimeError\0boom\0spec/a.rb:in x"))
    end

    it "is one digest for the same element missing at different lines of a page object" do
      digests = (1..20).map do |i|
        signature(exception_class: "Capybara::ElementNotFound", message: "Unable to find css \"#btn-#{i}\"",
                  app_frame: "spec/pages/login_page.rb:#{i + 10}:in 'LoginPage#submit'").digest
      end
      expect(digests.uniq.size).to eq(1)
    end

    it "differs for a different exception class" do
      expect(signature(exception_class: "ArgumentError").digest).not_to eq(signature.digest)
    end

    it "groups by a shared support frame but keeps different classes apart" do
      frame = "spec/support/helpers.rb:12:in 'click'"
      first = signature(exception_class: "Capybara::ElementNotFound", message: "x", app_frame: frame)
      again = signature(exception_class: "Capybara::ElementNotFound", message: "x", app_frame: frame.sub("12", "40"))
      other = signature(exception_class: "Selenium::WebDriver::Error::StaleElementReferenceError", message: "x",
                        app_frame: frame)
      expect(first.frame).to eq("spec/support/helpers.rb:in click")
      expect(again.digest).to eq(first.digest)
      expect(other.digest).not_to eq(first.digest)
    end
  end
end
