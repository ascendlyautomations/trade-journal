import type { ReconstructedLifecycleTrade } from "@/lib/integrations/tradovate/tradeReconstruction"
import type {
  BrokerContractMeta,
  TradovateBrokerTradeFinancials,
} from "@/lib/integrations/tradovate/tradovateBrokerTradeFinancials"
import { normalizedFuturesRootFromContractMeta } from "@/lib/integrations/tradovate/tradovateContractMeta"

/** Structured P&L trace for Tradovate sync diagnosis (no credentials). */
export function logTradovatePnLTrace(params: {
  lifecycle: ReconstructedLifecycleTrade
  contract?: BrokerContractMeta | null
  contractIdKey: string
  financials: TradovateBrokerTradeFinancials
  existingStoredPnL: number | null | undefined
  existingTicker: string | null | undefined
  calculatedPnL: number | null
  incomingPnL: number | null
  finalPnL: number | null
  incomingTicker: string
  finalTicker: string
  decision: string
}) {
  const enabled =
    process.env.TRADOVATE_PNL_DEBUG === "1" ||
    process.env.NODE_ENV !== "production"
  if (!enabled) return
  const { lifecycle, contract, contractIdKey, financials } = params
  const symbolRoot =
    normalizedFuturesRootFromContractMeta(contract) ??
    contract?.symbolRoot ??
    "null"

  console.info(
    [
      "[TradovatePnL]",
      `trade/lifecycle=${lifecycle.lifecycleKey}`,
      `contractId=${contractIdKey}`,
      `contractName=${contract?.contractName ?? contract?.executionContractName ?? "null"}`,
      `symbolRoot=${symbolRoot}`,
      `resolvedTicker=${financials.ticker}`,
      `points=${lifecycle.points}`,
      `contracts=${lifecycle.contracts}`,
      `valuePerPoint=${financials.valuePerPoint ?? "null"}`,
      `calculatedPnl=${params.calculatedPnL ?? "null"}`,
      `existingPnl=${params.existingStoredPnL ?? "null"}`,
      `incomingPnl=${params.incomingPnL ?? "null"}`,
      `finalPnl=${params.finalPnL ?? "null"}`,
      `existingTicker=${params.existingTicker ?? "null"}`,
      `incomingTicker=${params.incomingTicker}`,
      `finalTicker=${params.finalTicker}`,
      `grossPnl=${financials.grossPnL ?? "null"}`,
      `feeAmount=${financials.fees}`,
      `feeAvailability=${financials.feeAvailability}`,
      `journalPnl=${financials.journalPnL ?? "null"}`,
      `pnlSource=${financials.pnlSource}`,
      `pnlNullReason=${financials.pnlNullReason}`,
      `nullReason=${financials.nullReason}`,
      `decision=${params.decision}`,
    ].join(" ")
  )
}
