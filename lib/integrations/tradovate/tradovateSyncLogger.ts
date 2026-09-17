export type TradovateSyncFailureCategory =
  | "token_refresh_failure"
  | "provider_api_failure"
  | "fill_retrieval_failure"
  | "order_retrieval_failure"
  | "execution_persistence_failure"
  | "reconstruction_failure"
  | "supabase_write_failure"
  | "sync_lock"
  | "mapping_unavailable"
  | "sync_failed"

export type TradovateSyncFailureStage =
  | "mapping"
  | "lock"
  | "fill_list"
  | "order_list"
  | "persist_executions"
  | "resolve_contracts"
  | "reconstruct"
  | "fetch_fees"
  | "persist_trades"
  | "unknown"

export type TradovateSyncLogContext = {
  connectionId?: string
  mappingId?: string
  userId?: string
  provider?: string
  trigger?: string
  eventCategory?: string
  failureCategory?: TradovateSyncFailureCategory
  failureStage?: TradovateSyncFailureStage
  durationMs?: number
  fetched?: number
  newExecutions?: number
  tradesCreated?: number
  tradesUpdated?: number
  coalesced?: boolean
  reconnectCount?: number
  errorCode?: string
  httpStatus?: number
  providerHttpStatus?: number
  /** Final route HTTP outcome (sync_http_result). */
  ok?: boolean
  externalAccountId?: string
  providerUserId?: string
  /** Safe non-secret detail (never tokens/passwords). */
  detail?: string
}

export function logTradovateSync(
  message: string,
  context: TradovateSyncLogContext = {}
): void {
  console.info(
    JSON.stringify({
      scope: "tradovate_sync",
      message,
      ...context,
    })
  )
}
