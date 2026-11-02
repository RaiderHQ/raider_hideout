// Snapshots are untrusted HTML. Re-strip them here (the browser never trusts the
// recorder) and show them in a sandboxed, script-less frame.
const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src data:"
const REMOVE = "script, base, iframe, object, embed, frame, frameset, template, meta[http-equiv]"
const URL_ATTRIBUTES = ["href", "src", "action", "formaction"]

export function snapshotDocument(html) {
  const doc = new DOMParser().parseFromString(html, "text/html")
  doc.querySelectorAll(REMOVE).forEach((node) => node.remove())
  for (const node of doc.querySelectorAll("*")) {
    for (const attr of Array.from(node.attributes)) {
      const name = attr.name.toLowerCase()
      const value = attr.value.replace(/[\u0000- ]/g, "").toLowerCase()
      if (name.startsWith("on") || name === "shadowrootmode" || name === "shadowroot" || (URL_ATTRIBUTES.includes(name) && value.startsWith("javascript:"))) {
        node.removeAttribute(attr.name)
      }
    }
  }
  const meta = doc.createElement("meta")
  meta.setAttribute("http-equiv", "Content-Security-Policy")
  meta.setAttribute("content", CSP)
  doc.head.insertBefore(meta, doc.head.firstChild)
  return "<!DOCTYPE html>" + doc.documentElement.outerHTML
}

export function renderSnapshot(container, bytes, name) {
  const text = new TextDecoder("utf-8").decode(bytes)
  if (name.endsWith(".xml")) {
    const pre = document.createElement("pre")
    pre.textContent = text
    container.replaceChildren(pre)
    return pre
  }
  const frame = document.createElement("iframe")
  frame.setAttribute("sandbox", "")
  frame.dataset.testid = "trace-snapshot"
  frame.title = "Page snapshot"
  frame.srcdoc = snapshotDocument(text)
  container.replaceChildren(frame)
  return frame
}
