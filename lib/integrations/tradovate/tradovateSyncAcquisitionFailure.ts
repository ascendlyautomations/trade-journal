import type { TradovateImportAcquisitionStatus } from "./tradovateSyncCompleteness.ts"
import { tradovateAcquisitionErrorsIndicateAuthFailure } from "./tradovateAcquisitionAuth.ts"
import type {
  TradovateSyncFailureCategory,
  TradovateSyncFailureStage,
} from "./tradovateSyncLogger.ts"

export type TradovateSyncAcquisitionFailure = {
  authFailure: boolean
  status: "reconnect_required" | "error"
  errorCode: string
  error: string
  failureCategory: TradovateSyncFailureCategory
  failureStage: TradovateSyncFailureStage
}

export function resolveTradovateSyncAcquisitionFailure(params: {
  acquisitionStatus: TradovateImportAcquisitionStatus
  acquisitionErrors: string[]
}): TradovateSyncAcquisitionFailure | null {
  if (params.acquisitionStatus !== "IMPORT_FAILED") return null

  const authFailure = tradovateAcquisitionErrorsIndicateAuthFailure(
    params.acquisitionErrors
  )

  if (authFailure) {
    return {
      authFailure: true,
      status: "reconnect_required",
      errorCode: "reconnect_required",
      error:
        "Tradovate authorization failed for this connection. Reconnect and choose the environment (Demo or Live) that matches your account.",
      failureCategory: "token_refresh_failure",
      failureStage: "order_deps",
    }
  }

  return {
    authFailure: false,
    status: "error",
    errorCode: "import_acquisition_failed",
    error: "Could not retrieve trades from Tradovate.",
    failureCategory: "fill_retrieval_failure",
    failureStage: "fill_list",
  }
}
