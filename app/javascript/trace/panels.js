// Panels for the trace viewer. Every node is built with createElement and
// textContent; trace data is never parsed as HTML.
export const NOT_CAPTURED = "Not captured"
export const NOT_AVAILABLE = "Not available in this browser"
export const NOTHING = "Nothing during this step"
const STRATEGIES = ["id", "css", "xpath", "name", "link_text", "partial_link_text", "class_name", "tag_name"]
const NOTICES = {
  screenshots: "Older screenshots removed to keep the trace small",
  snapshots: "Older snapshots removed to keep the trace small",
  network: "Older network entries removed to keep the trace small",
  console: "Older console messages removed to keep the trace small"
}

function el(tag, { text, testid, className, attrs } = {}, ...children) {
  const node = document.createElement(tag)
  if (text !== undefined && text !== null) node.textContent = String(text)
  if (testid) node.dataset.testid = testid
  if (className) node.className = className
  for (const [key, value] of Object.entries(attrs || {})) node.setAttribute(key, value)
  node.append(...children)
  return node
}

const str = (value) => (value === undefined || value === null ? "" : String(value))

export function renderNotices(container, truncated) {
  const notices = Object.entries(NOTICES)
    .filter(([key]) => Number(truncated?.[key]) > 0)
    .map(([, copy]) => el("p", { text: copy, testid: "trace-notice", className: "text-sm text-neutral-mid" }))
  container.replaceChildren(...notices)
}

function stepLabel(step) {
  return step.element?.label || step.locator?.label || step.locator?.selector || ""
}

export function renderTimeline(container, steps, selectedIndex, onSelect) {
  const byParent = new Map()
  const known = new Set(steps.map((step) => step.index))
  for (const step of steps) {
    const parent = known.has(step.parent_index) && step.parent_index !== step.index ? step.parent_index : null
    if (!byParent.has(parent)) byParent.set(parent, [])
    byParent.get(parent).push(step)
  }
  const seen = new Set()
  const row = (step) => {
    const failed = step.status === "failed"
    const button = el("button", { testid: "trace-step", className: `text-left w-full px-2 py-1 rounded text-sm hover:bg-neutral-100 ${failed ? "text-red-700" : ""} ${step.index === selectedIndex ? "font-semibold bg-neutral-100" : ""}`, attrs: { type: "button" } })
    if (step.index === selectedIndex) button.setAttribute("aria-current", "true")
    const parts = [str(step.action || step.kind), step.name, stepLabel(step)].filter(Boolean)
    button.append(el("span", { text: parts.join(" ") }))
    if (step.waited_ms > 0) button.append(el("span", { text: ` waited ${step.waited_ms} ms`, className: "text-neutral-mid" }))
    if (failed) button.append(el("span", { text: " failed", testid: "trace-step-failed", className: "text-red-700" }))
    button.addEventListener("click", () => onSelect(step.index))
    return button
  }
  const build = (step) => {
    seen.add(step.index)
    const kids = (byParent.get(step.index) || []).filter((kid) => !seen.has(kid.index))
    const nested = kids.length ? el("ul", { className: "pl-4" }, ...kids.map(build)) : null
    if (step.kind === "group") {
      const details = el("details", {}, el("summary", {}, row(step)))
      details.open = true
      if (nested) details.append(nested)
      return el("li", {}, details)
    }
    return el("li", {}, row(step), ...(nested ? [nested] : []))
  }
  const roots = (byParent.get(null) || []).map(build)
  for (const step of steps) if (!seen.has(step.index)) roots.push(build(step))
  container.replaceChildren(el("ul", {}, ...roots))
}

function fact(label, value) {
  return value === "" ? [] : [el("dt", { text: label, className: "text-neutral-mid" }), el("dd", { text: value, className: "break-words" })]
}

// Builds the detail text and returns slots the controller fills with the screenshot and snapshot.
export function renderDetail(container, step) {
  const screenshot = el("div")
  const snapshot = el("div")
  const locator = step.locator
  const known = locator && STRATEGIES.includes(locator.strategy)
  const locatorText = locator ? (known ? `${locator.strategy}: ${str(locator.selector)}` : `Found by locator: ${str(locator.selector)}`) : ""
  const value = step.secret ? "Hidden (password field)" : str(step.value)
  const error = step.error ? `${str(step.error.class)}: ${str(step.error.message)}` : ""
  const facts = el("dl", { className: "grid grid-cols-[auto_minmax(0,1fr)] gap-x-3 gap-y-1 text-sm" },
    ...fact("Action", str(step.action || step.kind)), ...fact("Locator", locatorText), ...fact("Value", value),
    ...fact("Source", step.source ? `${str(step.source.file)}:${str(step.source.line)}` : ""),
    ...fact("Error", error), ...fact("Waited", step.waited_ms > 0 ? `${step.waited_ms} ms` : ""),
    ...fact("Retries", step.retries > 0 ? str(step.retries) : ""))
  container.replaceChildren(screenshot, snapshot, facts)
  return { screenshot, snapshot }
}

export function notCaptured(slot) {
  slot.replaceChildren(el("p", { text: NOT_CAPTURED, className: "text-sm text-neutral-mid" }))
}

// Shows the screenshot; draws the rect only when the page did not change since the previous step.
export function showScreenshot(slot, url, step, previous, dpr) {
  const img = el("img", { testid: "trace-screenshot", className: "block max-w-full h-auto", attrs: { src: url, alt: "Screenshot after the step" } })
  const wrap = el("div", { className: "relative inline-block max-w-full" }, img)
  slot.replaceChildren(wrap)
  const rect = step.rect
  if (!rect || !previous || previous.url !== step.url) return
  const place = () => {
    if (!img.naturalWidth) return
    const scale = (Number(dpr) > 0 ? Number(dpr) : 1)
    const box = el("div", { testid: "trace-rect", className: "absolute border-2 border-red-600 pointer-events-none", attrs: { title: "element before the action" } })
    box.style.left = `${(rect.x * scale / img.naturalWidth) * 100}%`
    box.style.top = `${(rect.y * scale / img.naturalHeight) * 100}%`
    box.style.width = `${(rect.width * scale / img.naturalWidth) * 100}%`
    box.style.height = `${(rect.height * scale / img.naturalHeight) * 100}%`
    wrap.append(box, el("p", { text: "element before the action", className: "text-xs text-neutral-mid" }))
  }
  if (img.complete) place()
  else img.addEventListener("load", place, { once: true })
}

function tabPanel(container, capability, rows, showAll, onToggle, describe) {
  if (capability === false) {
    container.replaceChildren(el("p", { text: NOT_AVAILABLE, className: "text-sm text-neutral-mid" }))
    return
  }
  const box = el("input", { attrs: { type: "checkbox" } })
  box.checked = showAll
  box.addEventListener("change", () => onToggle(box.checked))
  const toggle = el("label", { className: "text-sm flex items-center gap-2" }, box, el("span", { text: "Show all" }))
  const body = rows.length ? rows.map(describe) : [el("p", { text: NOTHING, className: "text-sm text-neutral-mid" })]
  container.replaceChildren(toggle, ...body)
}

const rowsFor = (list, selectedIndex, showAll) => (Array.isArray(list) ? list : []).filter((row) => showAll || row.step_index === selectedIndex)
const rowClass = "text-sm font-mono break-all border-b border-neutral-100 py-1"

export function renderNetwork(container, index, selectedIndex, showAll, onToggle) {
  tabPanel(container, index.capabilities?.network, rowsFor(index.network, selectedIndex, showAll), showAll, onToggle, (row) =>
    el("div", { testid: "trace-network-row", className: rowClass, text: [row.method, row.status, row.url, row.duration_ms === undefined ? "" : `${row.duration_ms} ms`, row.bytes === undefined ? "" : `${row.bytes} B`, row.error].map(str).filter(Boolean).join("  ") }))
}

export function renderConsole(container, index, selectedIndex, showAll, onToggle) {
  tabPanel(container, index.capabilities?.console, rowsFor(index.console, selectedIndex, showAll), showAll, onToggle, (row) =>
    el("div", { testid: "trace-console-row", className: rowClass, text: [row.level, row.text, row.source].map(str).filter(Boolean).join("  ") }))
}
