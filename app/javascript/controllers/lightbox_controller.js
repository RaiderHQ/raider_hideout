import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image"]

  open(event) {
    this.imageTarget.src = event.currentTarget.src
    this.imageTarget.alt = event.currentTarget.alt
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
