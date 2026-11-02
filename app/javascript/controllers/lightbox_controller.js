import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image"]

  open(event) {
    const el = event.currentTarget
    if (el.href && !el.src) event.preventDefault()
    this.imageTarget.src = el.src || el.href
    this.imageTarget.alt = el.alt || el.textContent.trim()
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
