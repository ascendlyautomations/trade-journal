import type { TradovateImportAcquisitionStatus } from "./tradovateSyncCompleteness.ts"
import type { TradovateFeeCoverageStatus } from "./tradovateSyncCompleteness.ts"
import type { TradovateFinancialReconciliationStatus } from "./tradovateFinancialReconciliationCore.ts"

export type TradovateSyncStageDurationsMs = {
  acquisition?: number
  persistExecutions?: number
  resolveContracts?: number
  reconstruct?: number
  fetchFees?: number
  fillPairValidation?: number
  persistTrades?: number
}

export type TradovateSyncSummaryPayload = {
  accountId: string
  acquisitionStatus: TradovateImportAcquisitionStatus
  orders: number
  dependencyFills: number
  supplementalFills: number
  uniqueFills: number
  ledgerExecutions: number
  newExecutions: number
  existingExecutions: number
  completedLifecycles: number
  tradesInserted: number
  tradesUpdated: number
  unresolvedContracts: number
  fillPairStatus: TradovateFinancialReconciliationStatus | "SKIPPED"
  fillPairDifference: number | null
  feeCoverage: TradovateFeeCoverageStatus
  grossPnl: number | null
  durationMs: number
  stageDurationsMs?: TradovateSyncStageDurationsMs
}

export function logTradovateSyncSummary(payload: TradovateSyncSummaryPayload): void {
  const stages = payload.stageDurationsMs
  console.info(
    [
      "[TradovateSyncSummary]",
      `accountId=${payload.accountId}`,
      `acquisitionStatus=${payload.acquisitionStatus}`,
      `orders=${payload.orders}`,
      `dependencyFills=${payload.dependencyFills}`,
      `supplementalFills=${payload.supplementalFills}`,
      `uniqueFills=${payload.uniqueFills}`,
      `ledgerExecutions=${payload.ledgerExecutions}`,
      `newExecutions=${payload.newExecutions}`,
      `existingExecutions=${payload.existingExecutions}`,
      `completedLifecycles=${payload.completedLifecycles}`,
      `tradesInserted=${payload.tradesInserted}`,
      `tradesUpdated=${payload.tradesUpdated}`,
      `unresolvedContracts=${payload.unresolvedContracts}`,
      `fillPairStatus=${payload.fillPairStatus}`,
      `fillPairDifference=${payload.fillPairDifference ?? "null"}`,
      `feeCoverage=${payload.feeCoverage}`,
      `grossPnl=${payload.grossPnl ?? "null"}`,
      `durationMs=${payload.durationMs}`,
      stages
        ? `stageMs=acq:${stages.acquisition ?? 0}|persist:${stages.persistExecutions ?? 0}|meta:${stages.resolveContracts ?? 0}|recon:${stages.reconstruct ?? 0}|fees:${stages.fetchFees ?? 0}|fillPair:${stages.fillPairValidation ?? 0}|trades:${stages.persistTrades ?? 0}`
        : "",
    ]
      .filter(Boolean)
      .join(" ")
  )
}
