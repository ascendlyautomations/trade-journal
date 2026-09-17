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

function safeDetail(value: string | undefined): string | undefined {
  if (!value) return undefined
  const trimmed = value.trim()
  if (!trimmed) return undefined
  return trimmed.slice(0, 160)
}

function emptyFailureSummary(
  patch: Partial<TradovateSyncSummary>
): TradovateSyncSummary {
  return {
    ok: false,
    status: "error",
    trigger: "manual",
    fetched: 0,
    newExecutions: 0,
    duplicateExecutions: 0,
    tradesCreated: 0,
    tradesUpdated: 0,
    newTradeIds: [],
    updatedTradeIds: [],
    openPositions: 0,
    ...patch,
  }
}

/** Existing success/failure body + optional diagnostics on non-success only. */
function syncResponseBody(params: {
  connectionId: string
  mappingId: string
  summary: TradovateSyncSummary
  accounts: Awaited<ReturnType<typeof attachSyncViewsToBrokerAccounts>>
  providerHttpStatus?: number
}) {
  const { connectionId, mappingId, summary, accounts, providerHttpStatus } =
    params
  const body: {
    ok: boolean
    connectionId: string
    mappingId: string
    summary: TradovateSyncSummary
    accounts: typeof accounts
    errorCode?: string
    failureStage?: TradovateSyncFailureStage
    failureCategory?: TradovateSyncFailureCategory
    providerHttpStatus?: number
    detail?: string
  } = {
    ok: summary.ok,
    connectionId,
    mappingId,
    summary,
    accounts,
  }

  if (!summary.ok) {
    if (summary.errorCode != null) body.errorCode = summary.errorCode
    if (summary.failureStage != null) body.failureStage = summary.failureStage
    if (summary.failureCategory != null) {
      body.failureCategory = summary.failureCategory
    }
    if (providerHttpStatus != null) body.providerHttpStatus = providerHttpStatus
    const detail = safeDetail(summary.error)
    if (detail != null) body.detail = detail
  }

  return body
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
  let providerHttpStatus: number | undefined
  try {
    summary = await syncTradovateBrokerAccount(integrationDb, {
      userId: user.id,
      connectionId,
      brokerIntegrationAccountId: mappingId,
      trigger: "manual",
    })
  } catch (err) {
    const errorCode =
      err instanceof TradovateApiError
        ? err.code
        : "route_unhandled_exception"
    const failureCategory: TradovateSyncFailureCategory =
      err instanceof TradovateApiError && err.code === "reconnect_required"
        ? "token_refresh_failure"
        : "sync_failed"
    const failureStage: TradovateSyncFailureStage = "unknown"
    const detail = safeDetail(
      err instanceof Error ? err.message : "unknown_error"
    )
    providerHttpStatus =
      err instanceof TradovateApiError ? err.httpStatus : undefined

    summary = emptyFailureSummary({
      error: detail,
      errorCode,
      failureCategory,
      failureStage,
    })

    return Response.json(
      syncResponseBody({
        connectionId,
        mappingId,
        summary,
        accounts: [],
        providerHttpStatus,
      }),
      { status: 400 }
    )
  }

  const httpStatus = httpStatusForSummary(summary)

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
  } catch {
    // Keep sync outcome; accounts enrichment is best-effort for the response.
  }

  return Response.json(
    syncResponseBody({
      connectionId,
      mappingId,
      summary,
      accounts: accountsWithSync,
      providerHttpStatus,
    }),
    { status: httpStatus }
  )
}
