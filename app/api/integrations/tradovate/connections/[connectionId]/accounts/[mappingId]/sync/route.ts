import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { attachSyncViewsToBrokerAccounts } from "@/lib/integrations/tradovate/runTradovateAccountTradeSync"
import { syncTradovateBrokerAccount } from "@/lib/integrations/tradovate/syncTradovateBrokerAccount"
import { logTradovateSync } from "@/lib/integrations/tradovate/tradovateSyncLogger"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 120

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = {
  params: Promise<{ connectionId: string; mappingId: string }>
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

  const summary = await syncTradovateBrokerAccount(integrationDb, {
    userId: user.id,
    connectionId,
    brokerIntegrationAccountId: mappingId,
    trigger: "manual",
  })

  const accounts = await listSafeBrokerIntegrationAccounts(integrationDb, {
    userId: user.id,
    provider: "tradovate",
    connectionId,
  })
  const accountsWithSync = await attachSyncViewsToBrokerAccounts(
    integrationDb,
    accounts
  )

  const status = summary.ok ? 200 : summary.status === "syncing" ? 409 : 400

  if (!summary.ok) {
    logTradovateSync("sync_http_result", {
      userId: user.id,
      connectionId,
      mappingId,
      trigger: "manual",
      httpStatus: status,
      errorCode: summary.errorCode ?? "unknown",
      failureCategory: summary.failureCategory ?? "sync_failed",
      failureStage: summary.failureStage ?? "unknown",
      detail: summary.error?.slice(0, 160),
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
    { status }
  )
}
