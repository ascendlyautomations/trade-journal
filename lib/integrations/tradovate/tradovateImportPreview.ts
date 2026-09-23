import type { SupabaseClient } from "@supabase/supabase-js"
import {
  computeTradovateBrokerTradeFinancials,
  type BrokerContractMeta,
} from "./tradovateBrokerTradeFinancials.ts"
import type { ReconstructedLifecycleTrade } from "./tradeReconstruction.ts"

/** Wire shape for Review Imported Trades — same financial projection as persist. */
export type TradovateImportPreviewTrade = {
  lifecycleKey: string
  contractId: string
  ticker: string
  direction: "Long" | "Short"
  contracts: number
  entryPrice: number
  exitPrice: number
  entryTime: string
  exitTime: string
  points: number
  pnl: number | null
  grossPnl: number | null
  fees: number
}

export function buildTradovateImportPreviewTrades(params: {
  completed: ReconstructedLifecycleTrade[]
  contracts: Map<string, BrokerContractMeta>
  feesByFillId:
    | Map<
        string,
        { clearingFee: number; exchangeFee: number; nfaFee: number; commission: number }
      >
    | Map<
        string,
        import("./tradovateFillFeeCoverageCore.ts").TradovateFillFeeRecord
      >
}): TradovateImportPreviewTrade[] {
  return params.completed.map((lifecycle) => {
    const contractIdKey = String(lifecycle.contractId).trim()
    const contract =
      params.contracts.get(contractIdKey) ??
      params.contracts.get(lifecycle.contractId)
    const financials = computeTradovateBrokerTradeFinancials({
      lifecycle,
      contract,
      contractIdKey,
      feesByFillId: params.feesByFillId,
    })
    return {
      lifecycleKey: lifecycle.lifecycleKey,
      contractId: contractIdKey,
      ticker: financials.ticker,
      direction: lifecycle.direction,
      contracts: lifecycle.contracts,
      entryPrice: lifecycle.entryPrice,
      exitPrice: lifecycle.exitPrice,
      entryTime: lifecycle.entryTime,
      exitTime: lifecycle.exitTime,
      points: lifecycle.points,
      pnl: financials.netPnL,
      grossPnl: financials.grossPnL,
      fees: financials.fees,
    }
  })
}

/** Preview import UI — lifecycles not yet present on `trades.broker_lifecycle_id`. */
export async function filterTradovateImportPreviewTrades(
  supabase: SupabaseClient,
  userId: string,
  previews: TradovateImportPreviewTrade[]
): Promise<TradovateImportPreviewTrade[]> {
  if (previews.length === 0) return []
  const keys = previews.map((p) => p.lifecycleKey)
  const { data: existing } = await supabase
    .from("trades")
    .select("broker_lifecycle_id")
    .eq("user_id", userId)
    .in("broker_lifecycle_id", keys)
  const existingKeys = new Set(
    (existing ?? [])
      .map((r) => String(r.broker_lifecycle_id ?? "").trim())
      .filter(Boolean)
  )
  return previews.filter((p) => !existingKeys.has(p.lifecycleKey))
}
