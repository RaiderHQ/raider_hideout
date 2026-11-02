module PhoneHelpers
  def at_phone_width(width = 360)
    browser = page.driver.browser
    browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 800, deviceScaleFactor: 1, mobile: true)
    yield
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  def expect_no_horizontal_scroll
    widths = page.evaluate_script("[document.documentElement.scrollWidth, window.innerWidth]")
    expect(widths.last).to be <= 500, "viewport is #{widths.last}px wide, not a phone width"
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
