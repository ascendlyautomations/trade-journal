import { isNumericTradovateContractKey } from "./tradovateContractMeta.ts"
import type { ReconstructedLifecycleTrade } from "./tradeReconstruction.ts"
import type { BrokerContractMeta } from "./tradovateContractMeta.ts"

export type TradovatePnLNullReason =
  | "ok"
  | "symbol_root_unavailable"
  | "contract_id_not_resolved"
  | "unsupported_contract"
  | "value_per_point_unavailable"
  | "points_unavailable"
  | "contracts_unavailable"
  | "execution_grouping_issue"
  | "missing_entry_or_exit"
  | "other"

export function deriveTradovatePnLNullReason(params: {
  lifecycle: ReconstructedLifecycleTrade
  contract?: BrokerContractMeta | null
  contractIdKey: string
  ticker: string
  valuePerPoint: number | null
  grossPnL: number | null
}): TradovatePnLNullReason {
  if (params.grossPnL != null) return "ok"

  const entry = Number(params.lifecycle.entryPrice)
  const exit = Number(params.lifecycle.exitPrice)
  if (!Number.isFinite(entry) || !Number.isFinite(exit)) {
    return "missing_entry_or_exit"
  }
  const contracts = Number(params.lifecycle.contracts)
  if (!Number.isFinite(contracts) || contracts <= 0) {
    return "contracts_unavailable"
  }
  const points = Number(params.lifecycle.points)
  if (!Number.isFinite(points)) {
    return "points_unavailable"
  }

  if (isNumericTradovateContractKey(params.ticker)) {
    if (!params.contract) return "contract_id_not_resolved"
    return "symbol_root_unavailable"
  }

  if (params.valuePerPoint == null || params.valuePerPoint <= 0) {
    return "value_per_point_unavailable"
  }

  return "other"
}
