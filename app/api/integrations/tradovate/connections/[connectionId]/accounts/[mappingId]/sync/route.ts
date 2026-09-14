import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import {
  attachSyncViewsToBrokerAccounts,
  runTradovateAccountTradeSync,
} from "@/lib/integrations/tradovate/runTradovateAccountTradeSync"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

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

  const summary = await runTradovateAccountTradeSync(
    integrationDb,
    user.id,
    connectionId,
    mappingId
  )

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
