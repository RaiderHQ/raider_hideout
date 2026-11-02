import { Controller } from "@hotwired/stimulus"
import { renderSnapshot } from "trace/snapshot"
import { notCaptured, renderConsole, renderDetail, renderNetwork, renderNotices, renderTimeline, showScreenshot } from "trace/panels"
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
    if (this.blobUrl) URL.revokeObjectURL(this.blobUrl)
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

  async render(trace) {
    this.trace = trace
    this.steps = Array.isArray(trace.index.steps) ? trace.index.steps : []
    this.showAll = { network: false, console: false }
    renderNotices(this.target("notices"), trace.index.truncated)
    this.showTab("network")
    const first = this.steps.find((step) => step.status === "failed") || this.steps[0]
    if (first) await this.select(first.index)
    else this.renderTabs()
  }

  async select(index) {
    const step = this.steps.find((candidate) => candidate.index === index)
    if (!step) return
    this.selected = index
    const token = (this.token = (this.token || 0) + 1)
    if (this.blobUrl) URL.revokeObjectURL(this.blobUrl)
    this.blobUrl = null
    this.target("notices").querySelector("[data-step-error]")?.remove()
    renderTimeline(this.target("timeline"), this.steps, index, (next) => this.select(next))
    this.renderTabs()
    const slots = renderDetail(this.target("detail"), step)
    const current = () => token === this.token && !this.abort.signal.aborted
    await Promise.all([
      this.load(step.screenshot, slots.screenshot, async (bytes, name) => {
        if (!current()) return
        const type = name.endsWith(".png") ? "image/png" : "image/jpeg"
        this.blobUrl = URL.createObjectURL(new Blob([bytes], { type }))
        const at = this.steps.indexOf(step)
        showScreenshot(slots.screenshot, this.blobUrl, step, this.steps[at - 1], this.trace.index.device_pixel_ratio)
      }, current),
      this.load(step.snapshot, slots.snapshot, (bytes, name) => current() && renderSnapshot(slots.snapshot, bytes, name), current)
    ])
  }

  // Reads one step entry; a failure is reported as a notice and leaves the rest usable.
  async load(name, slot, show, current) {
    const file = typeof name === "string" ? this.trace.entry(name) : null
    if (!file) return notCaptured(slot)
    try {
      await show(await file.read(), name)
    } catch (error) {
      if (!current()) return
      notCaptured(slot)
      const message = error instanceof TraceError ? error.message : new TraceError("corrupt zip").message
      const notice = document.createElement("p")
      notice.dataset.testid = "trace-error"
      notice.dataset.stepError = ""
      notice.textContent = message
      this.target("notices").append(notice)
    }
  }

  renderTabs() {
    const toggle = (key) => (checked) => {
      this.showAll[key] = checked
      this.renderTabs()
    }
    renderNetwork(this.target("network"), this.trace.index, this.selected, this.showAll.network, toggle("network"))
    renderConsole(this.target("console"), this.trace.index, this.selected, this.showAll.console, toggle("console"))
  }

  showTab(name) {
    for (const key of ["network", "console"]) {
      this.target(key).hidden = key !== name
      this.element.querySelector(`[data-tab=${key}]`)?.setAttribute("aria-selected", String(key === name))
    }
  }

  tab(event) {
    this.showTab(event.currentTarget.dataset.tab)
  }

  target(name) {
    return this.element.querySelector(`#trace-${name}`)
  }

  showError(message) {
    const notice = document.createElement("p")
    notice.dataset.testid = "trace-error"
    notice.textContent = message
    this.target("notices").replaceChildren(notice)
  }
}
