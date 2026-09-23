import { resolveEffectiveValuePerPoint } from "./futuresValuePerPointFallback.ts"
import {
  normalizedFuturesRootFromContractMeta,
  resolveBrokerTradeTicker,
  type BrokerContractMeta,
} from "./tradovateContractMeta.ts"
import { resolveEffectiveValuePerPointSource } from "./futuresValuePerPointFallback.ts"
import {
  sumLifecycleFeesWithAvailability,
  type TradovateFillFeeRecord,
} from "./tradovateFillFeeCoverageCore.ts"
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
  valuePerPointSource: "product" | "local_fallback" | "unresolved"
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
  feesByFillId:
    | Map<
        string,
        { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }
      >
    | Map<string, TradovateFillFeeRecord>
}): TradovateBrokerTradeFinancials {
  const ticker = resolveBrokerTradeTicker({
    contract: params.contract,
    contractId: params.contractIdKey,
  })
  const vppRoot =
    ticker || normalizedFuturesRootFromContractMeta(params.contract) || ""
  const valuePerPoint = resolveEffectiveValuePerPoint({
    symbolRoot: vppRoot,
    contractValuePerPoint: params.contract?.valuePerPoint ?? null,
  })
  const valuePerPointSource = resolveEffectiveValuePerPointSource({
    symbolRoot: vppRoot,
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
    const first = params.feesByFillId.values().next().value
    if (first && typeof first === "object" && "availability" in first) {
      const feeResult = sumLifecycleFeesWithAvailability(
        params.feesByFillId as Map<string, TradovateFillFeeRecord>,
        params.lifecycle.fillIds
      )
      fees = feeResult.fees
      netPnL = feeResult.hasUnavailable ? null : grossPnL - fees
    } else {
      fees = sumFillFees(
        params.feesByFillId as Map<
          string,
          { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }
        >,
        params.lifecycle.fillIds
      )
      netPnL = grossPnL - fees
    }
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
    valuePerPointSource,
    grossPnL,
    fees,
    netPnL,
    numericTicker: /^\d+$/.test(ticker.trim()),
    nullReason,
  }
}
