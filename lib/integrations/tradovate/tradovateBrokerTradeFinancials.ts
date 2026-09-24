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

export type TradovateLifecycleFeeAvailability = "COMPLETE" | "PARTIAL" | "UNAVAILABLE"

export type TradovateJournalPnLSource = "net" | "gross" | "none"

export type TradovateBrokerTradeFinancials = {
  ticker: string
  valuePerPoint: number | null
  valuePerPointSource: "product" | "local_fallback" | "unresolved"
  grossPnL: number | null
  fees: number
  netPnL: number | null
  feeAvailability: TradovateLifecycleFeeAvailability
  journalPnL: number | null
  pnlSource: TradovateJournalPnLSource
  pnlNullReason: TradovatePnLNullReason | "fees_partial_use_gross" | "economics_unresolved"
  numericTicker: boolean
  nullReason: TradovatePnLNullReason
}

function lifecycleFeeAvailability(
  fillIds: string[],
  feesByFillId: Map<string, TradovateFillFeeRecord>
): TradovateLifecycleFeeAvailability {
  if (fillIds.length === 0) return "COMPLETE"
  let known = 0
  let unavailable = 0
  for (const id of fillIds) {
    const row = feesByFillId.get(id)
    if (!row || row.availability === "UNAVAILABLE") unavailable += 1
    else known += 1
  }
  if (unavailable === 0) return "COMPLETE"
  if (known === 0) return "UNAVAILABLE"
  return "PARTIAL"
}

function resolveJournalPnL(params: {
  grossPnL: number | null
  netPnL: number | null
  feeAvailability: TradovateLifecycleFeeAvailability
  economicsNullReason: TradovatePnLNullReason
}): {
  journalPnL: number | null
  pnlSource: TradovateJournalPnLSource
  pnlNullReason: TradovateBrokerTradeFinancials["pnlNullReason"]
} {
  if (params.grossPnL == null) {
    return {
      journalPnL: null,
      pnlSource: "none",
      pnlNullReason: params.economicsNullReason,
    }
  }
  if (params.netPnL != null) {
    return {
      journalPnL: params.netPnL,
      pnlSource: "net",
      pnlNullReason: "ok",
    }
  }
  if (params.feeAvailability === "UNAVAILABLE" || params.feeAvailability === "PARTIAL") {
    return {
      journalPnL: params.grossPnL,
      pnlSource: "gross",
      pnlNullReason: "fees_partial_use_gross",
    }
  }
  return {
    journalPnL: params.grossPnL,
    pnlSource: "gross",
    pnlNullReason: "ok",
  }
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
  let feeAvailability: TradovateLifecycleFeeAvailability = "COMPLETE"
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
      const feeMap = params.feesByFillId as Map<string, TradovateFillFeeRecord>
      feeAvailability = lifecycleFeeAvailability(params.lifecycle.fillIds, feeMap)
      const feeResult = sumLifecycleFeesWithAvailability(
        feeMap,
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
  const journal = resolveJournalPnL({
    grossPnL,
    netPnL,
    feeAvailability,
    economicsNullReason: nullReason,
  })

  return {
    ticker,
    valuePerPoint,
    valuePerPointSource,
    grossPnL,
    fees,
    netPnL,
    feeAvailability,
    journalPnL: journal.journalPnL,
    pnlSource: journal.pnlSource,
    pnlNullReason: journal.pnlNullReason,
    numericTicker: /^\d+$/.test(ticker.trim()),
    nullReason,
  }
}
