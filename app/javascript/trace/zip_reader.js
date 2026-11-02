// Browser-side reader for untrusted Raider trace zips. No dependencies.
// Parses from the central directory, enforces size/name/type rules up front,
// and inflates entries lazily with a hard cap at the declared size.
export const MAX_ZIP_BYTES = 26 * 1024 * 1024
export const MAX_ENTRIES = 401
export const MAX_TOTAL_UNCOMPRESSED = 150 * 1024 * 1024
const RATIO_FLOOR = 1024 * 1024
const MAX_RATIO = 100
const NAME_RULE = /^trace\.json$|^steps\/\d{4}\.(jpg|png|html|xml)$/

export class TraceError extends Error {
  // reason: short lowercase phrase; exact: full user-facing copy shown as-is
  constructor(reason, { exact = false } = {}) {
    super(exact ? reason : `This trace can't be opened: ${reason}`)
    this.name = "TraceError"
    this.reason = reason
  }
}

const NOT_A_TRACE = "This file is not a Raider trace."
const NEWER = "This trace was made by a newer Raider. Update Hideout to open it."
const corrupt = () => new TraceError("corrupt zip")

export async function readZip(arrayBuffer) {
  if (arrayBuffer.byteLength > MAX_ZIP_BYTES) throw new TraceError("file too large")
  const view = new DataView(arrayBuffer)
  const bytes = new Uint8Array(arrayBuffer)
  const eocd = findEocd(view)

  const total = view.getUint16(eocd + 10, true)
  const cdSize = view.getUint32(eocd + 12, true)
  const cdOffset = view.getUint32(eocd + 16, true)
  if (total === 0xffff || cdSize === 0xffffffff || cdOffset === 0xffffffff) throw new TraceError("zip64 not supported")
  if (view.getUint16(eocd + 4, true) !== 0 || view.getUint16(eocd + 6, true) !== 0) throw corrupt()
  if (total > MAX_ENTRIES) throw new TraceError("too many entries")
  if (cdOffset + cdSize > eocd) throw corrupt()

  const entries = new Map()
  let pos = cdOffset
  let declaredTotal = 0
  for (let i = 0; i < total; i++) {
    if (pos + 46 > eocd || view.getUint32(pos, true) !== 0x02014b50) throw corrupt()
    const flags = view.getUint16(pos + 8, true)
    const method = view.getUint16(pos + 10, true)
    const compressed = view.getUint32(pos + 20, true)
    const uncompressed = view.getUint32(pos + 24, true)
    const nameLen = view.getUint16(pos + 28, true)
    const next = pos + 46 + nameLen + view.getUint16(pos + 30, true) + view.getUint16(pos + 32, true)
    const externalAttr = view.getUint32(pos + 38, true)
    const localOffset = view.getUint32(pos + 42, true)
    if (next > eocd) throw corrupt()
    if (compressed === 0xffffffff || uncompressed === 0xffffffff || localOffset === 0xffffffff) throw new TraceError("zip64 not supported")
    const name = asciiName(bytes, pos + 46, nameLen)
    pos = next

    if (name === null || !NAME_RULE.test(name)) throw new TraceError("entry name not allowed")
    if (entries.has(name)) throw new TraceError("duplicate entry")
    if (flags & 0x41) throw new TraceError("encrypted entry")
    if (method !== 0 && method !== 8) throw new TraceError("unsupported compression")
    if (((externalAttr >>> 16) & 0o170000) === 0o120000) throw new TraceError("symlink entry")
    if (uncompressed > RATIO_FLOOR && uncompressed > MAX_RATIO * compressed) throw new TraceError("suspicious compression ratio")
    declaredTotal += uncompressed
    if (declaredTotal > MAX_TOTAL_UNCOMPRESSED) throw new TraceError("file too large")

    const dataStart = localDataStart(view, bytes, localOffset, name, compressed)
    entries.set(name, { read: () => readEntry(bytes, dataStart, method, compressed, uncompressed) })
  }
  return entries
}

export async function loadTrace(entries) {
  const index = await readIndex(entries)
  const entry = (name) => (NAME_RULE.test(name) && entries.has(name) ? entries.get(name) : null)
  return { index, entry }
}

async function readIndex(entries) {
  const file = entries.get("trace.json")
  if (!file) throw new TraceError(NOT_A_TRACE, { exact: true })
  let index
  try {
    index = JSON.parse(new TextDecoder().decode(await file.read()))
  } catch (error) {
    if (error instanceof TraceError) throw error
    throw new TraceError(NOT_A_TRACE, { exact: true })
  }
  if (!index || typeof index !== "object" || index.format !== "raider-trace" || !Number.isInteger(index.version) || index.version < 1) {
    throw new TraceError(NOT_A_TRACE, { exact: true })
  }
  if (index.version > 1) throw new TraceError(NEWER, { exact: true })
  return index
}

function findEocd(view) {
  const last = view.byteLength - 22
  for (let pos = last; pos >= Math.max(0, last - 65535); pos--) {
    if (view.getUint32(pos, true) === 0x06054b50) return pos
  }
  throw corrupt()
}

function asciiName(bytes, start, length) {
  let name = ""
  for (let i = 0; i < length; i++) {
    const code = bytes[start + i]
    if (code < 0x20 || code > 0x7e) return null
    name += String.fromCharCode(code)
  }
  return name
}

function localDataStart(view, bytes, offset, centralName, compressed) {
  if (offset + 30 > view.byteLength || view.getUint32(offset, true) !== 0x04034b50) throw corrupt()
  const nameLen = view.getUint16(offset + 26, true)
  const start = offset + 30 + nameLen + view.getUint16(offset + 28, true)
  if (asciiName(bytes, offset + 30, nameLen) !== centralName) throw new TraceError("entry name mismatch")
  if (start + compressed > view.byteLength) throw corrupt()
  return start
}

async function readEntry(bytes, start, method, compressed, uncompressed) {
  const raw = bytes.subarray(start, start + compressed)
  if (method === 0) {
    if (compressed !== uncompressed) throw corrupt()
    return raw.slice()
  }
  if (typeof DecompressionStream === "undefined") throw new TraceError("browser cannot inflate zips")
  const reader = new Blob([raw]).stream().pipeThrough(new DecompressionStream("deflate-raw")).getReader()
  const out = new Uint8Array(uncompressed)
  let length = 0
  try {
    for (;;) {
      const { done, value } = await reader.read()
      if (done) break
      if (length + value.length > uncompressed) {
        await reader.cancel()
        throw new TraceError("entry larger than declared")
      }
      out.set(value, length)
      length += value.length
    }
  } catch (error) {
    if (error instanceof TraceError) throw error
    throw corrupt()
  }
  if (length !== uncompressed) throw corrupt()
  return out
}
