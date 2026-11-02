import { Controller } from "@hotwired/stimulus"

// Scrolls the failed-test card named by ?result= into view, so the page lands on it
// even when the URL fragment is lost (for example after sign-in).
export default class extends Controller {
  static values = { id: String }

  connect() {
    document.getElementById(this.idValue)?.scrollIntoView({ block: "start" })
  }
}
