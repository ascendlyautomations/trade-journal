import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { TradovateApiError } from "@/lib/integrations/tradovate/tradovateApiClient"
import { attachSyncViewsToBrokerAccounts } from "@/lib/integrations/tradovate/runTradovateAccountTradeSync"
import {
  syncTradovateBrokerAccount,
  type TradovateSyncSummary,
} from "@/lib/integrations/tradovate/syncTradovateBrokerAccount"
import { logTradovateSync } from "@/lib/integrations/tradovate/tradovateSyncLogger"
import type {
  TradovateSyncFailureCategory,
  TradovateSyncFailureStage,
} from "@/lib/integrations/tradovate/tradovateSyncLogger"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 120

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = {
  params: Promise<{ connectionId: string; mappingId: string }>
}

function httpStatusForSummary(summary: TradovateSyncSummary): number {
  if (summary.ok) return 200
  if (summary.status === "syncing") return 409
  return 400
}

function logSyncHttpResult(params: {
  userId: string
  connectionId: string
  mappingId: string
  httpStatus: number
  ok: boolean
  failureStage?: TradovateSyncFailureStage
  errorCode?: string
  failureCategory?: TradovateSyncFailureCategory
  providerHttpStatus?: number
  detail?: string
  durationMs?: number
}): void {
  logTradovateSync("sync_http_result", {
    userId: params.userId,
    connectionId: params.connectionId,
    mappingId: params.mappingId,
    trigger: "manual",
    httpStatus: params.httpStatus,
    ok: params.ok,
    failureStage: params.failureStage ?? "unknown",
    errorCode: params.errorCode ?? "unknown",
    failureCategory: params.failureCategory ?? "sync_failed",
    providerHttpStatus: params.providerHttpStatus,
    detail: params.detail?.slice(0, 160),
    durationMs: params.durationMs,
  })
}

export async function POST(_req: Request, context: RouteContext) {
  const user = await getRouteUser(_req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { connectionId, mappingId } = await context.params
  const owned = await loadOwnedBrokerConnection(integrationDb, {
    userId: user.id,
    connectionId,
    provider: "tradovate",
  })
  if (!owned) {
    return Response.json({ error: "Connection not found." }, { status: 404 })
  }

  let summary: TradovateSyncSummary
  try {
    summary = await syncTradovateBrokerAccount(integrationDb, {
      userId: user.id,
      connectionId,
      brokerIntegrationAccountId: mappingId,
      trigger: "manual",
    })
  } catch (err) {
    const providerHttpStatus =
      err instanceof TradovateApiError ? err.httpStatus : undefined
    const errorCode =
      err instanceof TradovateApiError
        ? err.code
        : "route_unhandled_exception"
    const detail =
      err instanceof Error ? err.message.slice(0, 160) : "unknown_error"

    logSyncHttpResult({
      userId: user.id,
      connectionId,
      mappingId,
      httpStatus: 500,
      ok: false,
      failureStage: "unknown",
      errorCode,
      failureCategory:
        err instanceof TradovateApiError && err.code === "reconnect_required"
          ? "token_refresh_failure"
          : "sync_failed",
      providerHttpStatus,
      detail,
    })

    // Preserve prior unhandled-throw response behavior after logging.
    throw err
  }

  const httpStatus = httpStatusForSummary(summary)

  // Log before account listing / response serialization so a 400 cannot leave
  // without sync_http_result even if later steps throw.
  logSyncHttpResult({
    userId: user.id,
    connectionId,
    mappingId,
    httpStatus,
    ok: summary.ok,
    failureStage: summary.failureStage,
    errorCode: summary.errorCode,
    failureCategory: summary.failureCategory,
    detail: summary.error,
    durationMs: summary.durationMs,
  })

  let accountsWithSync: Awaited<
    ReturnType<typeof attachSyncViewsToBrokerAccounts>
  > = []
  try {
    const accounts = await listSafeBrokerIntegrationAccounts(integrationDb, {
      userId: user.id,
      provider: "tradovate",
      connectionId,
    })
    accountsWithSync = await attachSyncViewsToBrokerAccounts(
      integrationDb,
      accounts
    )
  } catch (err) {
    const detail =
      err instanceof Error
        ? err.message.slice(0, 160)
        : "accounts_list_failed"
    logSyncHttpResult({
      userId: user.id,
      connectionId,
      mappingId,
      httpStatus,
      ok: summary.ok,
      failureStage: summary.failureStage ?? "unknown",
      errorCode: summary.errorCode ?? "accounts_enrichment_failed",
      failureCategory: summary.failureCategory ?? "sync_failed",
      detail: `post_sync_accounts: ${detail}`,
      durationMs: summary.durationMs,
    })
  }

  return Response.json(
    {
      ok: summary.ok,
      connectionId,
      mappingId,
      summary,
      accounts: accountsWithSync,
    },
    { status: httpStatus }
  )
}
