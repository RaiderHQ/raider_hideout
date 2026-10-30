require "selenium-webdriver"

# A full-page navigation (e.g. the data-turbo="false" token form) can replace the document between
# Capybara finding <html> and checking it. Chromedriver then reports the stale node as UnknownError
# "Node with given id does not belong to the document" instead of the W3C stale element reference
# error, so Capybara fails at once instead of re-finding the element in the new page.
module SeleniumStaleNodeTranslation
  DETACHED_NODE = "Node with given id does not belong to the document".freeze

  private

  def execute(...)
    super
  rescue Selenium::WebDriver::Error::UnknownError => e
    raise unless e.message.include?(DETACHED_NODE)

    raise Selenium::WebDriver::Error::StaleElementReferenceError, e.message
  end
end

Selenium::WebDriver::Remote::Bridge.prepend(SeleniumStaleNodeTranslation)
