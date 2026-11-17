export const TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX = 100

export function normalizeTradeRoomBroadcastStreamTitle(
  raw: unknown
): string | null {
  if (raw == null) return null
  const trimmed = String(raw).trim().replace(/\s+/g, " ")
  if (!trimmed) return null
  if (trimmed.length > TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX) {
    return trimmed.slice(0, TRADE_ROOM_BROADCAST_STREAM_TITLE_MAX)
  }
  return trimmed
}

export function validateTradeRoomBroadcastStreamTitle(
  raw: unknown
): { ok: true; title: string } | { ok: false; error: string } {
  const title = normalizeTradeRoomBroadcastStreamTitle(raw)
  if (!title) {
    return { ok: false, error: "Stream title is required (1–100 characters)." }
  }
  return { ok: true, title }
}

/** Safe single-line display (no HTML). */
export function formatBroadcastStreamTitleForDisplay(
  title: string | null | undefined
): string | null {
  const t = normalizeTradeRoomBroadcastStreamTitle(title)
  return t
}

/** UI: broadcaster name + custom stream title. */
export function formatLiveBroadcastHeadline(input: {
  broadcasterDisplayName?: string | null
  streamTitle?: string | null
  roomTitleFallback?: string | null
}): string {
  const name = input.broadcasterDisplayName?.trim() || "Trader"
  const title =
    formatBroadcastStreamTitleForDisplay(input.streamTitle) ||
    input.roomTitleFallback?.trim() ||
    "Live stream"
  return `${name} · ${title}`
}
