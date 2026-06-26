/** Trade detail page cache — trade row + owner profile per trade id. */

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
    sessions.delete(key)
    return null
  }
  return entry
}

export function writeTradeDetail(
  tradeId: string,
  snapshot: Omit<TradeDetailSnapshot, "tradeId" | "fetchedAt">
) {
  const key = String(tradeId).trim()
  if (!key) return
  sessions.set(key, {
    ...snapshot,
    tradeId: key,
    fetchedAt: Date.now(),
  })
}

export function invalidateTradeDetail(tradeId: string) {
  sessions.delete(String(tradeId).trim())
}
