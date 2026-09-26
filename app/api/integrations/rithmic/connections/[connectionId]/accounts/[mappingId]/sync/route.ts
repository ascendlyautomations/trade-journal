import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { attachSyncViewsToBrokerAccounts } from "@/lib/integrations/tradovate/runTradovateAccountTradeSync"
import { syncRithmicBrokerAccount } from "@/lib/integrations/rithmic/syncRithmicBrokerAccount"
import { sanitizeRithmicSyncRequestBody } from "@/lib/integrations/rithmic/rithmicConnectSafeResponse"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"
export const maxDuration = 120

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = {
  params: Promise<{ connectionId: string; mappingId: string }>
}

export async function POST(req: Request, context: RouteContext) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let transientPassword: string | null = null
  try {
    const raw = await req.json()
    transientPassword = sanitizeRithmicSyncRequestBody(raw)?.password ?? null
  } catch {
    transientPassword = null
  }

  const { connectionId, mappingId } = await context.params
  const owned = await loadOwnedBrokerConnection(integrationDb, {
    userId: user.id,
    connectionId,
    provider: "rithmic",
  })
  if (!owned) {
    return Response.json({ error: "Connection not found." }, { status: 404 })
  }

  const summary = await syncRithmicBrokerAccount(integrationDb, {
    userId: user.id,
    connectionId,
    brokerIntegrationAccountId: mappingId,
    trigger: "manual",
    transientPassword,
  })

  const accounts = await listSafeBrokerIntegrationAccounts(integrationDb, {
    userId: user.id,
    provider: "rithmic",
    connectionId,
  })
  const accountsWithSync = await attachSyncViewsToBrokerAccounts(
    integrationDb,
    accounts
  )

  const status = summary.ok ? 200 : summary.status === "syncing" ? 409 : 400
  const code = rithmicBrokerClientCode(summary)

  return Response.json(
    {
      ok: summary.ok,
      connectionId,
      mappingId,
      summary,
      accounts: accountsWithSync,
      ...(code ? { code, errorCode: summary.errorCode } : {}),
    },
    { status }
  )
}

/** Same stable client codes as Tradovate sync. iOS classifies from these, not prose. */
function rithmicBrokerClientCode(summary: {
  ok: boolean
  status: string
  errorCode?: string
}): string | undefined {
  if (summary.ok) return undefined
  const errorCode = summary.errorCode?.trim()
  if (summary.status === "syncing" || errorCode === "sync_in_progress") {
    return "BROKER_SYNC_IN_PROGRESS"
  }
  if (
    summary.status === "reconnect_required" ||
    errorCode === "reconnect_required" ||
    errorCode === "unauthorized" ||
    errorCode === "not_connected" ||
    errorCode === "rithmic_password_required"
  ) {
    return "BROKER_RECONNECT_REQUIRED"
  }
  if (errorCode === "provider_unavailable") return "BROKER_TEMPORARILY_UNAVAILABLE"
  return "BROKER_SYNC_FAILED"
}
