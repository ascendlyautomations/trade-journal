/** Trade row fields used to classify backtest vs live journal activity. */
export type BacktestClassifiableTrade = {
  mode?: string | null
  account_type?: string | null
}

/**
 * True when a trade is backtest activity (matches profile stats exclusion).
 * Checks both `mode` and `account_type` — some rows only set one field.
 */
export function isBacktestTrade(trade: BacktestClassifiableTrade): boolean {
  const mode = String(trade.mode ?? "").trim().toLowerCase()
  const type = String(trade.account_type ?? "").trim().toLowerCase()
  return mode === "backtest" || type === "backtest"
}

/** Exclude backtest trades from dashboard / trades-page performance pipelines. */
export function excludeBacktestTrades<T extends BacktestClassifiableTrade>(
  trades: T[]
): T[] {
  return trades.filter((t) => !isBacktestTrade(t))
}
