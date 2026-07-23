/**
 * UUID v4 compatible with iOS WKWebView / older WebViews where
 * `crypto.randomUUID` is missing but `crypto.getRandomValues` exists.
 */
export function randomId(): string {
  const c = globalThis.crypto

  if (typeof c?.randomUUID === "function") {
    return c.randomUUID()
  }

  if (typeof c?.getRandomValues !== "function") {
    throw new Error("Secure random UUID unavailable in this environment")
  }

  const bytes = new Uint8Array(16)
  c.getRandomValues(bytes)

  // RFC 4122 version 4 / variant 1
  bytes[6] = (bytes[6]! & 0x0f) | 0x40
  bytes[8] = (bytes[8]! & 0x3f) | 0x80

  let hex = ""
  for (let i = 0; i < bytes.length; i++) {
    hex += bytes[i]!.toString(16).padStart(2, "0")
  }

  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}
