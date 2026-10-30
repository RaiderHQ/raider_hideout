# Class strings copied from raider_desktop components (Button, StatusIndicators).
module UiHelper
  BUTTON_BASE = "inline-flex items-center justify-center gap-2 min-w-[150px] px-5 py-2.5 text-sm " \
                "font-semibold rounded-md tracking-wide transition-all duration-200"
  BUTTON_VARIANTS = {
    primary: "bg-ruby text-white hover:shadow-card-hover",
    secondary: "bg-ruby-sub text-neutral-dk border border-neutral-bdr hover:bg-ruby-glow",
    disabled: "bg-neutral-bdr text-neutral-mid cursor-not-allowed",
    success: "bg-status-ok text-white hover:shadow-card-hover",
    outline: "bg-transparent text-ruby border border-ruby hover:bg-ruby-sub",
    danger: "bg-status-err text-white hover:shadow-card-hover"
  }.freeze
  STATUS_KINDS = { "passed" => :pass, "failed" => :fail, "flaky" => :flaky, "quarantined" => :quarantine }.freeze
  PILL_STYLES = {
    pass: "text-status-ok bg-status-ok-bg", fail: "text-status-err bg-status-err-bg",
    idle: "text-neutral-mid bg-neutral-lt", flaky: "text-accent-gold bg-accent-gold-bg",
    quarantine: "text-status-quarantine bg-status-quarantine-bg"
  }.freeze
  DOT_STYLES = { pass: "bg-status-ok", fail: "bg-status-err", idle: "bg-neutral-mid", flaky: "bg-accent-gold",
                quarantine: "bg-status-quarantine" }.freeze
  PILL_BASE = "inline-block text-[11px] font-semibold uppercase tracking-wider px-2.5 py-0.5 rounded-md flex-shrink-0"
  PANEL_BASE = "bg-neutral-wh rounded-lg shadow-card border border-neutral-bdr"

  def button_classes(variant = :primary, disabled: false, extra: nil)
    style = BUTTON_VARIANTS.fetch(disabled ? :disabled : variant)
    [ BUTTON_BASE, ("hover:-translate-y-px" unless disabled), style, extra ].compact.join(" ")
  end

  def status_pill(status)
    tag.span(status, class: "#{PILL_BASE} #{PILL_STYLES[status_kind(status)]}")
  end

  def status_dot(status, title: nil)
    tag.span("", class: "inline-block w-2 h-2 rounded-full flex-shrink-0 #{DOT_STYLES[status_kind(status)]}", title: title)
  end

  def panel(padding: "p-6", extra: nil, &block)
    tag.div(class: [ PANEL_BASE, padding, extra ].compact.join(" "), &block)
  end

  private

  def status_kind(status)
    STATUS_KINDS.fetch(status.to_s, :idle)
  end
end
