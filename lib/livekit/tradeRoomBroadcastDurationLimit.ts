/** Video broadcast duration limits (not Trade Room general voice). */
export const TRADE_ROOM_BROADCAST_MAX_DURATION_MS = 2 * 60 * 60 * 1000
export const TRADE_ROOM_BROADCAST_COOLDOWN_MS = 15 * 60 * 1000
export const TRADE_ROOM_BROADCAST_DURATION_END_REASON = "duration_limit"

export const BROADCAST_DURATION_LIMIT_COOLDOWN_MESSAGE =
  "You reached the 2-hour broadcast limit. You can start another video stream in 15 minutes."

export const BROADCAST_DURATION_LIMIT_VIEWER_MESSAGE =
  "This livestream ended after reaching the 2-hour broadcast limit."

export const BROADCAST_DURATION_LIMIT_BROADCASTER_MESSAGE =
  "Your stream reached the 2-hour limit and was ended automatically."

export function computeBroadcastExpiresAt(fromMs: number = Date.now()): string {
  return new Date(fromMs + TRADE_ROOM_BROADCAST_MAX_DURATION_MS).toISOString()
}

export function isBroadcastPastExpiresAt(
  expiresAt: string | null | undefined,
  nowMs: number = Date.now()
): boolean {
  if (!expiresAt?.trim()) return false
  const t = Date.parse(expiresAt)
  return Number.isFinite(t) && t <= nowMs
}

export function broadcastRemainingMs(
  expiresAt: string | null | undefined,
  nowMs: number = Date.now()
): number | null {
  if (!expiresAt?.trim()) return null
  const t = Date.parse(expiresAt)
  if (!Number.isFinite(t)) return null
  return Math.max(0, t - nowMs)
}

export function liveKitTokenTtlCapSeconds(
  expiresAt: string | null | undefined,
  defaultTtl: number,
  nowMs: number = Date.now()
): number {
  const remaining = broadcastRemainingMs(expiresAt, nowMs)
  if (remaining == null) return defaultTtl
  if (remaining <= 0) return 60
  return Math.min(defaultTtl, Math.max(60, Math.floor(remaining / 1000)))
}

export type BroadcastDurationWarningLevel = "none" | "15m" | "5m" | "expired"

export function broadcastDurationWarningLevel(
  remainingMs: number | null
): BroadcastDurationWarningLevel {
  if (remainingMs == null) return "none"
  if (remainingMs <= 0) return "expired"
  if (remainingMs <= 5 * 60 * 1000) return "5m"
  if (remainingMs <= 15 * 60 * 1000) return "15m"
  return "none"
}

export function formatBroadcastCountdown(remainingMs: number): string {
  const totalSec = Math.ceil(remainingMs / 1000)
  const h = Math.floor(totalSec / 3600)
  const m = Math.floor((totalSec % 3600) / 60)
  const s = totalSec % 60
  if (h > 0) {
    return `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
  }
  return `${m}:${String(s).padStart(2, "0")}`
}

export function broadcastDurationWarningCopy(
  level: BroadcastDurationWarningLevel
): string | null {
  switch (level) {
    case "15m":
      return "15 minutes left on this broadcast."
    case "5m":
      return "5 minutes left — the stream will end automatically at the 2-hour limit."
    case "expired":
      return BROADCAST_DURATION_LIMIT_BROADCASTER_MESSAGE
    default:
      return null
  }
}