import { resolveEffectiveValuePerPoint } from "./futuresValuePerPointFallback.ts"
import {
  resolveBrokerTradeTicker,
  type BrokerContractMeta,
} from "./tradovateContractMeta.ts"
import {
  computeFuturesGrossPnl,
  sumFillFees,
  type ReconstructedLifecycleTrade,
} from "./tradeReconstruction.ts"
import {
  deriveTradovatePnLNullReason,
  type TradovatePnLNullReason,
} from "./tradovatePnLNullReason.ts"

export type { BrokerContractMeta }

export type TradovateBrokerTradeFinancials = {
  ticker: string
  valuePerPoint: number | null
  grossPnL: number | null
  fees: number
  netPnL: number | null
  numericTicker: boolean
  nullReason: TradovatePnLNullReason
}

/** Pure financial projection for Tradovate/Rithmic broker lifecycle rows (tests + persist). */
export function computeTradovateBrokerTradeFinancials(params: {
  lifecycle: ReconstructedLifecycleTrade
  contract?: BrokerContractMeta | null
  contractIdKey: string
  feesByFillId: Map<
    string,
    { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }
  >
}): TradovateBrokerTradeFinancials {
  const ticker = resolveBrokerTradeTicker({
    contract: params.contract,
    contractId: params.contractIdKey,
  })
  const valuePerPoint = resolveEffectiveValuePerPoint({
    symbolRoot: ticker,
    contractValuePerPoint: params.contract?.valuePerPoint ?? null,
  })
  let grossPnL: number | null = null
  let fees = 0
  let netPnL: number | null = null
  if (valuePerPoint != null && valuePerPoint > 0) {
    grossPnL = computeFuturesGrossPnl(
      params.lifecycle.direction,
      params.lifecycle.entryPrice,
      params.lifecycle.exitPrice,
      params.lifecycle.contracts,
      valuePerPoint
    )
    fees = sumFillFees(params.feesByFillId, params.lifecycle.fillIds)
    netPnL = grossPnL - fees
  }
  const nullReason = deriveTradovatePnLNullReason({
    lifecycle: params.lifecycle,
    contract: params.contract,
    contractIdKey: params.contractIdKey,
    ticker,
    valuePerPoint,
    grossPnL,
  })

  return {
    ticker,
    valuePerPoint,
    grossPnL,
    fees,
    netPnL,
    numericTicker: /^\d+$/.test(ticker.trim()),
    nullReason,
  }
}
