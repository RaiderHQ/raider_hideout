require "rails_helper"

RSpec.describe UiHelper, type: :helper do
  it "builds desktop button classes" do
    expect(helper.button_classes(:primary)).to include("bg-ruby text-white hover:shadow-card-hover", "hover:-translate-y-px", "rounded-md")
    expect(helper.button_classes(:outline)).to include("text-ruby border border-ruby")
  end

  it "uses the disabled style and drops the hover lift when disabled" do
    classes = helper.button_classes(:primary, disabled: true)
    expect(classes).to include("bg-neutral-bdr text-neutral-mid cursor-not-allowed")
    expect(classes).not_to include("hover:-translate-y-px")
  end

  it "rejects unknown variants" do
    expect { helper.button_classes(:fancy) }.to raise_error(KeyError)
  end

  it "maps statuses to pill styles" do
    expect(helper.status_pill("passed")).to include("text-status-ok bg-status-ok-bg").and include(">passed<")
    expect(helper.status_pill("failed")).to include("text-status-err bg-status-err-bg")
    expect(helper.status_pill("flaky")).to include("text-accent-gold bg-accent-gold-bg")
    expect(helper.status_pill("skipped")).to include("text-neutral-mid bg-neutral-lt")
    expect(helper.status_pill("quarantined")).to include("text-status-quarantine bg-status-quarantine-bg").and include(">quarantined<")
    expect(helper.status_dot("quarantined")).to include("bg-status-quarantine")
  end

  it "renders dots and panels" do
    expect(helper.status_dot("failed", title: "run 3")).to include("bg-status-err").and include('title="run 3"')
    expect(helper.panel { "hi" }).to include("bg-neutral-wh rounded-lg shadow-card").and include("hi")
  end

  it "pads panels with p-6 by default and lets callers swap the padding" do
    expect(helper.panel { "x" }[/class="([^"]*)"/, 1].split).to include("p-6")
    tight = helper.panel(padding: "p-2") { "x" }[/class="([^"]*)"/, 1].split
    expect(tight).to include("p-2")
    expect(tight).not_to include("p-6")
  end
end
