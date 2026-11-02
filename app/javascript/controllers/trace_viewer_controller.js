import { Controller } from "@hotwired/stimulus"
import { renderSnapshot } from "trace/snapshot"
import { MAX_ZIP_BYTES, TraceError, readZip, loadTrace } from "trace/zip_reader"

// Fetches the trace zip, reads it in the browser and hands it to the renderer.
export default class extends Controller {
  static values = { url: String }

  async connect() {
    this.abort = new AbortController()
    try {
      const trace = await loadTrace(await readZip(await this.download()))
      await this.render(trace)
    } catch (error) {
      if (this.abort.signal.aborted) return
      this.showError(error instanceof TraceError ? error.message : "This trace can't be opened: download failed")
    }
  }

  disconnect() {
    this.abort?.abort()
  }

  async download() {
    const response = await fetch(this.urlValue, { credentials: "same-origin", signal: this.abort.signal })
    if (!response.ok) throw new TraceError("download failed")
    if (Number(response.headers.get("Content-Length")) > MAX_ZIP_BYTES) throw new TraceError("file too large")
    const reader = response.body.getReader()
    const chunks = []
    let total = 0
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      total += value.length
      if (total > MAX_ZIP_BYTES) {
        await reader.cancel()
        throw new TraceError("file too large")
      }
      chunks.push(value)
    }
    return await new Blob(chunks).arrayBuffer()
  }

  // Placeholder timeline; the real renderer replaces this.
  async render({ index, entry }) {
    const timeline = this.element.querySelector("#trace-timeline")
    for (const step of index.steps || []) {
      const item = document.createElement("li")
      item.dataset.testid = "trace-step"
      item.textContent = String(step.action ?? "")
      timeline.append(item)
    }
    await this.showSnapshot(entry, (index.steps || [])[0])
  }

  // Minimal selection until the detail panel lands: the first step.
  async showSnapshot(entry, step) {
    const name = step?.snapshot
    const file = typeof name === "string" ? entry(name) : null
    if (!file) return
    try {
      renderSnapshot(this.element.querySelector("#trace-detail"), await file.read(), name)
    } catch (error) {
      if (this.abort.signal.aborted) return
      this.showError(error instanceof TraceError ? error.message : "This trace can't be opened: snapshot unreadable")
    }
  }

  showError(message) {
    const notice = document.createElement("p")
    notice.dataset.testid = "trace-error"
    notice.textContent = message
    this.element.querySelector("#trace-notices").replaceChildren(notice)
  }
}
