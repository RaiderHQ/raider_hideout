import { Controller } from "@hotwired/stimulus"

// Submits the surrounding form when a filter select changes (replaces inline onchange, which the CSP blocks).
export default class extends Controller {
  submit() {
    this.element.form?.requestSubmit()
  }
}
