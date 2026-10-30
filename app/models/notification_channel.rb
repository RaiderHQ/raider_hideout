class NotificationChannel < ApplicationRecord
  KINDS = %w[slack teams email].freeze

  # Email channels need SMTP (spec 2026-10-29 §6.2).
  def self.available_kinds = Hideout.mail_enabled? ? KINDS : KINDS - %w[email]

  BRANCH_FILTERS = %w[default all pattern].freeze
  MAX_RECIPIENTS = 20
  TEAMS_HOST_SUFFIXES = %w[.logic.azure.com .powerplatform.com .powerautomate.com].freeze

  belongs_to :project
  has_many :notification_deliveries, dependent: :destroy

  encrypts :webhook_url

  before_validation :strip_webhook_url
  before_validation :normalize_recipients

  validates :kind, inclusion: { in: KINDS }
  validates :name, presence: true, length: { maximum: 100 }
  validates :branch_filter, inclusion: { in: BRANCH_FILTERS }
  validates :branch_pattern, presence: true, length: { maximum: 200 }, if: -> { branch_filter == "pattern" }
  validates :pass_rate_below, numericality: { only_integer: true, in: 1..100 }, allow_nil: true
  validate :webhook_url_matches_kind, if: -> { KINDS.include?(kind) && webhook? }
  validate :recipients_are_valid, if: -> { kind == "email" }

  def webhook?
    kind != "email"
  end

  def recipient_list
    recipients.to_s.split(/[,\n]/).map { |address| address.strip.downcase }.reject(&:blank?).uniq
  end

  def masked_target
    return mask(webhook_url) if webhook?

    count = recipient_list.size
    label = "#{count} #{'recipient'.pluralize(count)}"
    include_owner ? "#{label} + owners & admins" : label
  end

  def redact(text)
    return text.to_s if webhook_url.blank?

    masked = mask(webhook_url)
    base = webhook_url.split("?").first
    forms = [ webhook_url, base ].flat_map { |form| encoded_forms(form) }.uniq.sort_by { |form| -form.length }
    forms.reduce(text.to_s) { |out, form| out.gsub(form) { masked } }
  end

  private

  # Raw, JSON-escaped (\/), HTML-escaped (&amp;) and both combined.
  def encoded_forms(form)
    html = form.gsub("&") { "&amp;" }
    [ form, html ].flat_map { |f| [ f, f.gsub("/") { "\\/" } ] }
  end

  def mask(url)
    return "" if url.blank?

    "#{URI.parse(url).host}/…/#{url[-4..]}"
  rescue URI::InvalidURIError
    "…/#{url[-4..]}"
  end

  def webhook_url_matches_kind
    uri = parse_uri(webhook_url)
    host = uri&.host&.downcase
    return if host.present? && (extra_host?(host) || kind_host?(uri, host))

    errors.add(:webhook_url, kind == "slack" ? "must be a Slack incoming webhook URL" : "must be a Teams Workflows webhook URL")
  end

  def kind_host?(uri, host)
    return false unless uri.scheme&.downcase == "https"

    case kind
    when "slack" then host == "hooks.slack.com"
    when "teams" then TEAMS_HOST_SUFFIXES.any? { |suffix| host.end_with?(suffix) }
    else false
    end
  end

  def extra_host?(host)
    Array(Rails.configuration.x.notifications.extra_webhook_hosts).include?(host)
  end

  def parse_uri(value)
    URI.parse(value.to_s.strip)
  rescue URI::InvalidURIError
    nil
  end

  def strip_webhook_url
    self.webhook_url = webhook_url.strip if webhook_url.is_a?(String)
  end

  def normalize_recipients
    self.recipients = recipient_list.join("\n") if kind == "email"
  end

  def recipients_are_valid
    list = recipient_list
    errors.add(:recipients, "can't be blank") if list.empty? && !include_owner
    errors.add(:recipients, "must have at most #{MAX_RECIPIENTS} addresses") if list.size > MAX_RECIPIENTS
    invalid = list.grep_v(URI::MailTo::EMAIL_REGEXP)
    return if invalid.empty?

    shown = invalid.first(3).join(", ")
    shown += " and #{invalid.size - 3} more" if invalid.size > 3
    errors.add(:recipients, "contains invalid addresses: #{shown}")
  end
end
