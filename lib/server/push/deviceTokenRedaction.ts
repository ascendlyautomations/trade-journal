/** Redacts APNs device tokens for server logs — never log the full value. */
export function redactDeviceToken(token: string | null | undefined): string {
  const normalized = String(token ?? "").trim()
  if (!normalized) return "[empty]"
  if (normalized.length <= 12) return "[redacted]"
  return `${normalized.slice(0, 8).toLowerCase()}…${normalized.slice(-4).toLowerCase()}`
}
