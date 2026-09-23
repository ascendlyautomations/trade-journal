import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { TradovateApiError } from "@/lib/integrations/tradovate/tradovateApiClient"
import { attachSyncViewsToBrokerAccounts } from "@/lib/integrations/tradovate/runTradovateAccountTradeSync"
import { clearManualImportPreviewHold } from "@/lib/integrations/tradovate/tradovateManualImportHold"
import {
  syncTradovateBrokerAccount,
  type TradovateSyncMode,
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

/** Stable client contract — iOS must not infer reconnect from free-text errors. */
function brokerClientCode(summary: TradovateSyncSummary): string | undefined {
  if (summary.ok) return undefined
  if (summary.status === "syncing") return "BROKER_SYNC_IN_PROGRESS"
  const errorCode = summary.errorCode?.trim()
  if (
    summary.status === "reconnect_required" ||
    errorCode === "reconnect_required" ||
    errorCode === "unauthorized" ||
    errorCode === "not_connected"
  ) {
    return "BROKER_RECONNECT_REQUIRED"
  }
  if (errorCode === "provider_unavailable") {
    return "BROKER_TEMPORARILY_UNAVAILABLE"
  }
  if (errorCode === "account_mapping_required") {
    return "BROKER_ACCOUNT_MAPPING_REQUIRED"
  }
  return "BROKER_SYNC_FAILED"
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
    code?: string
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
    const code = brokerClientCode(summary)
    if (code != null) body.code = code
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

type SyncBody = { mode?: string }

function parseSyncMode(req: Request, body: SyncBody): TradovateSyncMode | "cancel_preview" {
  const fromBody = body.mode?.trim().toLowerCase()
  if (fromBody === "preview" || fromBody === "import" || fromBody === "cancel_preview") {
    return fromBody
  }
  const url = new URL(req.url)
  const fromQuery = url.searchParams.get("mode")?.trim().toLowerCase()
  if (fromQuery === "preview" || fromQuery === "import" || fromQuery === "cancel_preview") {
    return fromQuery
  }
  return "import"
}

export async function POST(req: Request, context: RouteContext) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: SyncBody = {}
  try {
    body = (await req.json()) as SyncBody
  } catch {
    body = {}
  }
  const mode = parseSyncMode(req, body)

  const { connectionId, mappingId } = await context.params

  if (mode === "cancel_preview") {
    await clearManualImportPreviewHold(integrationDb, mappingId)
    const summary: TradovateSyncSummary = {
      ok: true,
      status: "success",
      trigger: "manual",
      fetched: 0,
      newExecutions: 0,
      duplicateExecutions: 0,
      tradesCreated: 0,
      tradesUpdated: 0,
      newTradeIds: [],
      updatedTradeIds: [],
      openPositions: 0,
      importPreviewTrades: [],
      persistCalled: false,
    }
    return Response.json({
      ok: true,
      connectionId,
      mappingId,
      summary,
      accounts: [],
    })
  }
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
      mode,
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
