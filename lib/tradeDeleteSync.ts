/** Client-side sync when a journal trade is deleted or visibility changes (linked clips stay). */

export const TRADE_DELETED_EVENT = "tj-trade-deleted"
export const TRADE_VISIBILITY_EVENT = "tj-trade-visibility"

export type TradeDeletedDetail = {
  tradeId: string
  userId?: string
}

export type TradeVisibilityDetail = {
  tradeId: string
  userId?: string
  isPublic: boolean
}

export const REEL_TRADE_UNLINK_PATCH = {
  trade_id: null,
  kind: null,
  trades: null,
} as const

export function notifyTradeDeleted(detail: TradeDeletedDetail) {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent(TRADE_DELETED_EVENT, { detail }))
}

export function notifyTradeVisibilityChanged(detail: TradeVisibilityDetail) {
  if (typeof window === "undefined") return
  window.dispatchEvent(new CustomEvent(TRADE_VISIBILITY_EVENT, { detail }))
}

function patchEmbeddedTradeVisibility(
  trades: unknown,
  isPublic: boolean
): unknown {
  if (!trades) return trades
  if (Array.isArray(trades)) {
    return trades.map((row) =>
      row && typeof row === "object"
        ? { ...(row as Record<string, unknown>), is_public: isPublic }
        : row
    )
  }
  if (typeof trades === "object") {
    return { ...(trades as Record<string, unknown>), is_public: isPublic }
  }
  return trades
}

export function patchFeedItemTradeVisibility(
  item: {
    feedKind?: string
    trade_id?: string | null
    trades?: unknown
  },
  tradeId: string,
  isPublic: boolean
) {
  const tid = tradeId.trim()
  if (!tid || item.feedKind !== "reel") return item
  if (String(item.trade_id ?? "") !== tid) return item
  return {
    ...item,
    trades: patchEmbeddedTradeVisibility(item.trades, isPublic),
  }
}

export function patchReelRowTradeVisibility<
  T extends { trade_id?: string | null; trades?: unknown },
>(row: T, tradeId: string, isPublic: boolean): T {
  const tid = tradeId.trim()
  if (!tid || String(row.trade_id ?? "") !== tid) return row
  return {
    ...row,
    trades: patchEmbeddedTradeVisibility(row.trades, isPublic),
  }
}

export function patchReelRowUnlinkedFromTrade<
  T extends { trade_id?: string | null },
>(row: T, tradeId: string): T {
  const tid = tradeId.trim()
  if (!tid || String(row.trade_id ?? "") !== tid) return row
  return { ...row, ...REEL_TRADE_UNLINK_PATCH }
}

export function patchFeedItemUnlinkedFromTrade(
  item: { feedKind?: string; trade_id?: string | null },
  tradeId: string
) {
  const tid = tradeId.trim()
  if (!tid || item.feedKind !== "reel") return item
  if (String(item.trade_id ?? "") !== tid) return item
  return { ...item, ...REEL_TRADE_UNLINK_PATCH }
}
