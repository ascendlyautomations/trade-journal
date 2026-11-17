import { formatShortDateEST } from "./formatDate.ts"
import { formatTradeClockTime } from "./tradeDisplayFormat.ts"
import { publicAccountBadgeFromTrade } from "./publicAccountPrivacy.ts"
import { isCopyTradedTrade } from "./tradeCopyTrading.ts"

export function publicTradeCaptionFromRow(trade: Record<string, unknown>): string | null {
  const raw = trade.public_description
  if (raw == null) return null
  const s = String(raw).trim()
  return s || null
}

export function publicSocialHeaderAccountBadge(trade: Record<string, unknown>): string | null {
  if (isCopyTradedTrade(trade)) return null
  return publicAccountBadgeFromTrade(trade)
}

export function tradeExecutionDateLabel(value: unknown): string | null {
  if (value == null || value === "") return null
  return formatShortDateEST(String(value)) || null
}

export function tradeExecutionClockLabel(value: unknown): string | null {
  const clock = formatTradeClockTime(value)
  if (!clock || clock === "—") return null
  const raw = String(value ?? "").trim()
  if (raw.includes("T")) {
    const d = new Date(raw)
    if (!Number.isNaN(d.getTime())) {
      return d.toLocaleTimeString(undefined, {
        hour: "numeric",
        minute: "2-digit",
      })
    }
  }
  return clock
}
