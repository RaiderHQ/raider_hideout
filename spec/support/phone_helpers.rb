module PhoneHelpers
  DESKTOP_SIZE = [ 1400, 1400 ].freeze

  def at_phone_width(width = 360)
    page.driver.browser.manage.window.resize_to(width, 800)
    yield
  ensure
    page.driver.browser.manage.window.resize_to(*DESKTOP_SIZE)
  end

  def expect_no_horizontal_scroll
    widths = page.evaluate_script("[document.documentElement.scrollWidth, window.innerWidth]")
    expect(widths.first).to be <= widths.last
  end

  def expect_tap_targets(selector)
    heights = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(#{selector.to_json})).map(function (el) {
        return [el.textContent.trim(), el.getBoundingClientRect().height];
      })
    JS
    expect(heights).not_to be_empty
    short = heights.select { |_, height| height < 44 }
    expect(short).to be_empty, "tap targets under 44px: #{short.inspect}"
  end
end

RSpec.configure { |c| c.include PhoneHelpers, type: :system }
