import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "./database.types.ts"
import type { TradeForLeaderboard } from "./leaderboardChart.ts"
import {
  createReadTimeoutSignal,
  classifyServerReadError,
  logServerReadOutcome,
  SupabaseReadError,
  supabaseResultToError,
  withServerReadRetry,
  type ServerReadErrorClassification,
} from "./serverReadRetry.ts"

export const LEADERBOARD_TRADE_ROWS_PAGE_SIZE = 1000
export const LEADERBOARD_TRADE_ROWS_MAX = 3000
const DEFAULT_PAGE_TIMEOUT_MS = 25_000

export type LeaderboardTradeRowsPaginateResult = {
  trades: TradeForLeaderboard[]
  partial: boolean
}

export type PaginateLeaderboardTradeRowsOptions = {
  maxRows?: number
  pageTimeoutMs?: number
  correlationId?: string
  operation?: string
  signal?: AbortSignal
}

async function fetchLeaderboardTradeRowsPage(
  client: SupabaseClient<Database>,
  params: {
    afterCreatedAt: string | null
    afterUserId: string | null
    limit: number
    signal?: AbortSignal
    pageTimeoutMs: number
  }
): Promise<TradeForLeaderboard[]> {
  const timeout = createReadTimeoutSignal(params.pageTimeoutMs, params.signal)
  try {
    const rpcBuilder = client.rpc("leaderboard_trade_rows_page", {
      p_after_created_at: params.afterCreatedAt ?? undefined,
      p_after_user_id: params.afterUserId ?? undefined,
      p_limit: params.limit,
    })
    const rpcRequest =
      typeof rpcBuilder.abortSignal === "function"
        ? rpcBuilder.abortSignal(timeout.signal)
        : rpcBuilder
    const { data, error } = await rpcRequest
    const readError = supabaseResultToError(error, "leaderboard_trade_rows_page")
    if (readError) throw readError
    return (data ?? []) as TradeForLeaderboard[]
  } finally {
    timeout.dispose()
  }
}

export async function paginateLeaderboardTradeRows(
  client: SupabaseClient<Database>,
  options?: PaginateLeaderboardTradeRowsOptions
): Promise<LeaderboardTradeRowsPaginateResult> {
  const started = performance.now()
  const operation = options?.operation ?? "leaderboard_trade_rows_scan"
  const correlationId =
    options?.correlationId ??
    `lb-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`
  const capped = Math.max(
    1,
    Math.min(options?.maxRows ?? LEADERBOARD_TRADE_ROWS_MAX, LEADERBOARD_TRADE_ROWS_MAX)
  )
  const pageTimeoutMs = options?.pageTimeoutMs ?? DEFAULT_PAGE_TIMEOUT_MS

  const all: TradeForLeaderboard[] = []
  let afterCreatedAt: string | null = null
  let afterUserId: string | null = null
  let totalAttempts = 0
  let partial = false
  let lastErrorClass: ServerReadErrorClassification | undefined

  while (all.length < capped) {
    if (options?.signal?.aborted) break
    const limit = Math.min(LEADERBOARD_TRADE_ROWS_PAGE_SIZE, capped - all.length)
    let pageAttempts = 0

    try {
      const batch = await withServerReadRetry(
        async (attempt) => {
          pageAttempts = attempt
          return fetchLeaderboardTradeRowsPage(client, {
            afterCreatedAt,
            afterUserId,
            limit,
            signal: options?.signal,
            pageTimeoutMs,
          })
        },
        { operation, signal: options?.signal }
      )
      totalAttempts += pageAttempts

      if (batch.length === 0) break
      all.push(...batch)
      if (batch.length < limit) break

      const last = batch[batch.length - 1]
      afterCreatedAt = last.created_at
      afterUserId = last.user_id
    } catch (err) {
      totalAttempts += pageAttempts
      lastErrorClass =
        err instanceof SupabaseReadError
          ? err.classification
          : classifyServerReadError(err)
      partial = all.length > 0
      logServerReadOutcome({
        operation,
        durationMs: performance.now() - started,
        attempts: totalAttempts,
        outcome: partial ? "partial" : "failure",
        errorClass: lastErrorClass ?? "unknown",
        correlationId,
        rows: all.length,
        detail: err instanceof Error ? err.message : String(err),
      })
      break
    }
  }

  if (!partial && all.length >= 0) {
    logServerReadOutcome({
      operation,
      durationMs: performance.now() - started,
      attempts: Math.max(1, totalAttempts),
      outcome: "success",
      correlationId,
      rows: all.length,
    })
  }

  return { trades: all, partial }
}
