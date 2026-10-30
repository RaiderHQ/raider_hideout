import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source"]

  copy(event) {
    navigator.clipboard.writeText(this.sourceTarget.textContent.trim())
    event.currentTarget.textContent = "Copied"
  }
}
