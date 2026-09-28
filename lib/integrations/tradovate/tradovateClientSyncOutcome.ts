import type { TradovateImportAcquisitionStatus } from "./tradovateSyncCompleteness.ts"

/** When false, clients must not show “no new trades / up to date”. */
export function tradovateClientSyncOk(params: {
  acquisitionStatus: TradovateImportAcquisitionStatus
  fetchedFillCount: number
}): boolean {
  if (params.acquisitionStatus === "IMPORT_FAILED") return false
  if (
    params.acquisitionStatus === "IMPORT_SUCCESS_PARTIAL" &&
    params.fetchedFillCount === 0
  ) {
    return false
  }
  return true
}

export function tradovateClientSyncErrorForIncompletePartial(params: {
  acquisitionStatus: TradovateImportAcquisitionStatus
  fetchedFillCount: number
  ledgerExecutionCountAtStart: number
}): { errorCode: string; error: string } | null {
  if (
    params.acquisitionStatus !== "IMPORT_SUCCESS_PARTIAL" ||
    params.fetchedFillCount !== 0
  ) {
    return null
  }
  if (params.ledgerExecutionCountAtStart > 0) {
    return {
      errorCode: "import_partial_no_new_fills",
      error:
        "Import could not retrieve new Tradovate fills. Sync again to retry.",
    }
  }
  return {
    errorCode: "import_incomplete_no_fills",
    error:
      "Tradovate did not return any fills for this account. Sync again or reconnect if the issue continues.",
  }
}
