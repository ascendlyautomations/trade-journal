export type TradeChecklistSignals = {
  tradeCount: number
  hasPublicTrade: boolean
  firstPrivateTradeId: string | null
}

/** Derive checklist trade signals from the warmed trades cache (avoids 3 duplicate queries). */
export function deriveTradeChecklistSignalsFromTrades(
  trades: readonly { id?: unknown; is_public?: boolean | null; mode?: string | null }[]
): TradeChecklistSignals {
  let hasPublicTrade = false
  let firstPrivateTradeId: string | null = null

  for (const trade of trades) {
    if (trade.is_public === true) {
      hasPublicTrade = true
    }
    if (
      firstPrivateTradeId == null &&
      trade.is_public !== true &&
      trade.mode !== "backtest"
    ) {
      firstPrivateTradeId = trade.id != null ? String(trade.id) : null
    }
  }

  return {
    tradeCount: trades.length,
    hasPublicTrade,
    firstPrivateTradeId,
  }
}
