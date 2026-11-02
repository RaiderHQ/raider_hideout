import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel"]

  select(event) {
    this.show(event.currentTarget.dataset.kind)
  }

  key(event) {
    if (event.key !== "ArrowRight" && event.key !== "ArrowLeft") return
    const step = event.key === "ArrowRight" ? 1 : -1
    const index = this.tabTargets.indexOf(event.currentTarget)
    const next = this.tabTargets[(index + step + this.tabTargets.length) % this.tabTargets.length]
    event.preventDefault()
    this.show(next.dataset.kind)
    next.focus()
  }

  show(kind) {
    this.tabTargets.forEach((tab) => {
      const selected = tab.dataset.kind === kind
      tab.setAttribute("aria-selected", String(selected))
      tab.tabIndex = selected ? 0 : -1
    })
    this.panelTargets.forEach((panel) => { panel.hidden = panel.dataset.kind !== kind })
  }
}
