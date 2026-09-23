import { isNumericTradovateContractKey } from "./tradovateContractMeta.ts"
import { normalizeFuturesSymbol } from "../../normalizeFuturesSymbol.ts"

/** Human futures root (MNQ), not a Tradovate numeric contract id. */
export function isAuthoritativeFuturesTicker(ticker: string | null | undefined): boolean {
  const t = String(ticker ?? "").trim()
  if (!t) return false
  if (isNumericTradovateContractKey(t)) return false
  const normalized = normalizeFuturesSymbol(t)
  return Boolean(normalized && !isNumericTradovateContractKey(normalized))
}

export type BrokerTradeFinancialMergeInput = {
  existingPnL: number | null | undefined
  existingTicker: string | null | undefined
  incomingPnL: number | null
  incomingTicker: string
}

export type BrokerTradeFinancialMergeResult = {
  finalPnL: number | null
  finalTicker: string
  decision: string
}

/**
 * Reconcile incoming broker-derived pnl/ticker with persisted trade fields.
 * Never replace known-good values with null or numeric contract-id tickers.
 */
export function mergeBrokerTradeFinancialFields(
  input: BrokerTradeFinancialMergeInput
): BrokerTradeFinancialMergeResult {
  const existingPnL =
    input.existingPnL != null && Number.isFinite(Number(input.existingPnL))
      ? Number(input.existingPnL)
      : null
  const incomingPnL =
    input.incomingPnL != null && Number.isFinite(Number(input.incomingPnL))
      ? Number(input.incomingPnL)
      : null
  const existingTicker = String(input.existingTicker ?? "").trim()
  const incomingTicker = String(input.incomingTicker ?? "").trim()

  const existingTickerAuthoritative = isAuthoritativeFuturesTicker(existingTicker)
  const incomingTickerAuthoritative = isAuthoritativeFuturesTicker(incomingTicker)

  let finalTicker = incomingTicker
  let tickerDecision = "use_incoming_ticker"

  if (!incomingTicker && existingTickerAuthoritative) {
    finalTicker = normalizeFuturesSymbol(existingTicker) || existingTicker
    tickerDecision = "keep_existing_ticker_over_empty_incoming"
  } else if (existingTickerAuthoritative && !incomingTickerAuthoritative) {
    finalTicker = normalizeFuturesSymbol(existingTicker) || existingTicker
    tickerDecision = "keep_existing_ticker_over_numeric_or_empty_incoming"
  } else if (
    existingTickerAuthoritative &&
    incomingTickerAuthoritative &&
    existingTicker !== incomingTicker
  ) {
    finalTicker = incomingTicker
    tickerDecision = "use_incoming_resolved_ticker"
  } else if (!existingTickerAuthoritative && incomingTickerAuthoritative) {
    finalTicker = incomingTicker
    tickerDecision = "upgrade_ticker_from_numeric_to_symbol"
  } else if (!existingTicker && incomingTicker) {
    finalTicker = incomingTicker
    tickerDecision = "set_ticker_on_empty_existing"
  }

  let finalPnL = incomingPnL
  let pnlDecision = "use_incoming_pnl"

  if (existingPnL != null && incomingPnL == null) {
    finalPnL = existingPnL
    pnlDecision = "keep_existing_pnl_over_null_incoming"
  } else if (existingPnL == null && incomingPnL != null) {
    finalPnL = incomingPnL
    pnlDecision = "set_pnl_from_incoming"
  } else if (existingPnL != null && incomingPnL != null) {
    finalPnL = incomingPnL
    pnlDecision = "use_incoming_pnl_both_present"
  }

  const decision = `${pnlDecision};${tickerDecision}`
  return { finalPnL, finalTicker, decision }
}
