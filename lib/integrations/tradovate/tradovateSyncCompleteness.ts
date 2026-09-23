import type { TradovateFillAcquisitionStats } from "./tradovateFillAcquisitionCore.ts"
import type { TradovateFinancialReconciliationStatus } from "./tradovateFinancialReconciliationCore.ts"

export type TradovateImportAcquisitionStatus =
  | "IMPORT_SUCCESS_COMPLETE"
  | "IMPORT_SUCCESS_PARTIAL"
  | "IMPORT_FAILED"

export type TradovateFeeCoverageStatus = "COMPLETE" | "PARTIAL" | "UNAVAILABLE"

export function deriveTradovateImportAcquisitionStatus(params: {
  stats: TradovateFillAcquisitionStats
  acquisitionErrors: string[]
  mergedFillCount: number
  importAborted?: boolean
}): TradovateImportAcquisitionStatus {
  if (params.importAborted) return "IMPORT_FAILED"
  if (params.mergedFillCount === 0 && params.stats.orderDepsFailed) {
    return "IMPORT_FAILED"
  }
  const partial =
    params.stats.orderDepsFailed ||
    params.stats.fillListFailed ||
    params.stats.fillLdepsBatchErrors > 0 ||
    params.acquisitionErrors.length > 0
  return partial ? "IMPORT_SUCCESS_PARTIAL" : "IMPORT_SUCCESS_COMPLETE"
}

export function deriveTradovateFeeCoverageStatus(params: {
  fillIds: string[]
  feeBatchErrors: string[]
  fees: Map<string, { availability: string }>
}): TradovateFeeCoverageStatus {
  if (params.fillIds.length === 0) return "COMPLETE"
  if (params.feeBatchErrors.length > 0) return "PARTIAL"
  for (const id of params.fillIds) {
    const row = params.fees.get(id)
    if (!row || row.availability === "UNAVAILABLE") return "PARTIAL"
  }
  return "COMPLETE"
}

export function mapReconciliationToFillPairStatus(
  status: TradovateFinancialReconciliationStatus
): string {
  return status
}
