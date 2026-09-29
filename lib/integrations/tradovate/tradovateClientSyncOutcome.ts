import type { TradovateFillAcquisitionStats } from "./tradovateFillAcquisitionCore.ts"
import type { TradovateImportAcquisitionStatus } from "./tradovateSyncCompleteness.ts"

/** Client-facing sync result when provider calls succeeded (or true failure). */
export type TradovateClientSyncOutcome =
  | "trades_found"
  | "up_to_date"
  | "no_available_trade_history"
  | "provider_failure"

export function tradovateProviderAcquisitionHealthy(params: {
  acquisitionStatus: TradovateImportAcquisitionStatus
  stats: Pick<
    TradovateFillAcquisitionStats,
    "orderDepsFailed" | "fillListFailed" | "fillLdepsBatchErrors"
  >
  acquisitionErrors: string[]
}): boolean {
  if (params.acquisitionStatus === "IMPORT_FAILED") return false
  if (params.stats.orderDepsFailed) return false
  if (params.stats.fillListFailed) return false
  if (params.stats.fillLdepsBatchErrors > 0) return false
  if (params.acquisitionErrors.length > 0) return false
  return true
}

export type TradovateClientSyncResult = {
  ok: boolean
  syncOutcome: TradovateClientSyncOutcome
  errorCode?: string
  error?: string
}

export function deriveTradovateClientSyncResult(params: {
  acquisitionStatus: TradovateImportAcquisitionStatus
  stats: Pick<
    TradovateFillAcquisitionStats,
    "orderDepsFailed" | "fillListFailed" | "fillLdepsBatchErrors"
  >
  acquisitionErrors: string[]
  fetchedFillCount: number
  ledgerExecutionCountAtStart: number
  newExecutions: number
  importPreviewTradeCount: number
}): TradovateClientSyncResult {
  const healthy = tradovateProviderAcquisitionHealthy({
    acquisitionStatus: params.acquisitionStatus,
    stats: params.stats,
    acquisitionErrors: params.acquisitionErrors,
  })

  const hasTradesToShow =
    params.fetchedFillCount > 0 ||
    params.newExecutions > 0 ||
    params.importPreviewTradeCount > 0

  if (hasTradesToShow) {
    return { ok: true, syncOutcome: "trades_found" }
  }

  if (healthy) {
    if (params.ledgerExecutionCountAtStart > 0) {
      return { ok: true, syncOutcome: "up_to_date" }
    }
    return {
      ok: true,
      syncOutcome: "no_available_trade_history",
      errorCode: "broker_no_available_trade_history",
    }
  }

  if (
    params.ledgerExecutionCountAtStart > 0 &&
    params.acquisitionStatus === "IMPORT_SUCCESS_PARTIAL"
  ) {
    return {
      ok: false,
      syncOutcome: "provider_failure",
      errorCode: "import_partial_no_new_fills",
      error:
        "Import could not retrieve new Tradovate fills. Sync again to retry.",
    }
  }

  if (params.acquisitionStatus === "IMPORT_FAILED") {
    return {
      ok: false,
      syncOutcome: "provider_failure",
      errorCode: "import_failed",
      error: "Could not retrieve trades from Tradovate.",
    }
  }

  return {
    ok: false,
    syncOutcome: "provider_failure",
    errorCode: "import_failed",
    error: "Could not retrieve trades from Tradovate.",
  }
}

/** @deprecated Use deriveTradovateClientSyncResult */
export function tradovateClientSyncOk(params: {
  acquisitionStatus: TradovateImportAcquisitionStatus
  fetchedFillCount: number
  ledgerExecutionCountAtStart: number
  historicalBackfillComplete: boolean
  stats?: Pick<
    TradovateFillAcquisitionStats,
    "orderDepsFailed" | "fillListFailed" | "fillLdepsBatchErrors"
  >
  acquisitionErrors?: string[]
  newExecutions?: number
  importPreviewTradeCount?: number
}): boolean {
  return deriveTradovateClientSyncResult({
    acquisitionStatus: params.acquisitionStatus,
    stats: params.stats ?? {
      orderDepsFailed: false,
      fillListFailed: false,
      fillLdepsBatchErrors: 0,
    },
    acquisitionErrors: params.acquisitionErrors ?? [],
    fetchedFillCount: params.fetchedFillCount,
    ledgerExecutionCountAtStart: params.ledgerExecutionCountAtStart,
    newExecutions: params.newExecutions ?? 0,
    importPreviewTradeCount: params.importPreviewTradeCount ?? 0,
  }).ok
}

/** @deprecated Use deriveTradovateClientSyncResult */
export function tradovateClientSyncErrorForIncompletePartial(params: {
  acquisitionStatus: TradovateImportAcquisitionStatus
  fetchedFillCount: number
  ledgerExecutionCountAtStart: number
  historicalBackfillComplete: boolean
  stats?: Pick<
    TradovateFillAcquisitionStats,
    "orderDepsFailed" | "fillListFailed" | "fillLdepsBatchErrors"
  >
  acquisitionErrors?: string[]
}): { errorCode: string; error: string } | null {
  const result = deriveTradovateClientSyncResult({
    acquisitionStatus: params.acquisitionStatus,
    stats: params.stats ?? {
      orderDepsFailed: false,
      fillListFailed: false,
      fillLdepsBatchErrors: 0,
    },
    acquisitionErrors: params.acquisitionErrors ?? [],
    fetchedFillCount: params.fetchedFillCount,
    ledgerExecutionCountAtStart: params.ledgerExecutionCountAtStart,
    newExecutions: 0,
    importPreviewTradeCount: 0,
  })
  if (result.ok || !result.errorCode) return null
  return { errorCode: result.errorCode, error: result.error ?? "" }
}
