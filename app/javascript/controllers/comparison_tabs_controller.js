import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  select(event) {
    const kind = event.currentTarget.dataset.kind
    this.tabTargets.forEach((tab) => tab.setAttribute("aria-selected", String(tab.dataset.kind === kind)))
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.kind !== kind })
  }
}
