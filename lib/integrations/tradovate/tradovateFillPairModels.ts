export type TradovatePositionRaw = {
  id?: number | string
  accountId?: number | string
  contractId?: number | string
}

export type TradovateFillPairRaw = {
  id?: number | string
  positionId?: number | string
  buyFillId?: number | string
  sellFillId?: number | string
  qty?: number
  buyPrice?: number
  sellPrice?: number
  active?: boolean
}

/** Normalized FillPair for validation (broker entity IDs, not TradeTraxs trade ids). */
export type NormalizedTradovateFillPair = {
  id: string
  positionId: string | null
  buyFillId: string
  sellFillId: string
  qty: number
  buyPrice: number
  sellPrice: number
  active: boolean
}

export function normalizeTradovateFillPairRow(
  raw: TradovateFillPairRaw
): NormalizedTradovateFillPair | null {
  if (raw.id == null || raw.buyFillId == null || raw.sellFillId == null) return null
  const qty = Number(raw.qty)
  const buyPrice = Number(raw.buyPrice)
  const sellPrice = Number(raw.sellPrice)
  if (!Number.isFinite(qty) || qty <= 0) return null
  if (!Number.isFinite(buyPrice) || !Number.isFinite(sellPrice)) return null
  return {
    id: String(raw.id),
    positionId: raw.positionId != null ? String(raw.positionId) : null,
    buyFillId: String(raw.buyFillId),
    sellFillId: String(raw.sellFillId),
    qty,
    buyPrice,
    sellPrice,
    active: raw.active !== false,
  }
}

export function dedupeTradovateFillPairsById(
  pairs: NormalizedTradovateFillPair[]
): NormalizedTradovateFillPair[] {
  const byId = new Map<string, NormalizedTradovateFillPair>()
  for (const pair of pairs) {
    byId.set(pair.id, pair)
  }
  return [...byId.values()]
}
