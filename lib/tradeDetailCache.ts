/** Trade detail page cache — trade row + owner profile per trade id. */

import { isNativeIos } from "@/lib/nativePlatform"
import { persistTradeDetail } from "@/lib/nativeSilentCacheBridge"

const DEFAULT_STALE_MS = 5 * 60 * 1000

export type TradeDetailSnapshot = {
  tradeId: string
  trade: any | null
  ownerProfile: {
    id: string
    username?: string | null
    name?: string | null
    avatar_url?: string | null
  } | null
  sessionUserId: string | undefined
  fetchedAt: number
}

const sessions = new Map<string, TradeDetailSnapshot>()

export function readTradeDetail(tradeId: string): TradeDetailSnapshot | null {
  const key = String(tradeId).trim()
  if (!key) return null
  const entry = sessions.get(key)
  if (!entry) return null
  if (Date.now() - entry.fetchedAt > DEFAULT_STALE_MS) {
    if (!(typeof window !== "undefined" && isNativeIos())) {
      sessions.delete(key)
      return null
    }
  }
  return entry
}

export function writeTradeDetail(
  tradeId: string,
  snapshot: Omit<TradeDetailSnapshot, "tradeId" | "fetchedAt">
) {
  const key = String(tradeId).trim()
  if (!key) return
  const full: TradeDetailSnapshot = {
    ...snapshot,
    tradeId: key,
    fetchedAt: Date.now(),
  }
  sessions.set(key, full)
  persistTradeDetail(key, full)
}

export function seedTradeDetail(tradeId: string, snapshot: TradeDetailSnapshot) {
  const key = String(tradeId).trim()
  if (!key || sessions.has(key)) return
  if (!snapshot || typeof snapshot !== "object") return
  sessions.set(key, { ...snapshot, tradeId: key })
}

export function invalidateTradeDetail(tradeId: string) {
  sessions.delete(String(tradeId).trim())
}
