import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { runTradovateAccountDiscovery } from "@/lib/integrations/tradovate/runTradovateAccountDiscovery"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = { params: Promise<{ connectionId: string }> }

export async function POST(_req: Request, context: RouteContext) {
  const user = await getRouteUser(_req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { connectionId } = await context.params
  const owned = await loadOwnedBrokerConnection(integrationDb, {
    userId: user.id,
    connectionId,
    provider: "tradovate",
  })
  if (!owned) {
    return Response.json({ error: "Connection not found." }, { status: 404 })
  }

  const discovery = await runTradovateAccountDiscovery(integrationDb, user.id, connectionId)
  const accounts = await listSafeBrokerIntegrationAccounts(integrationDb, {
    userId: user.id,
    provider: "tradovate",
    connectionId,
  })

  let state = "connected"
  if (!discovery.ok) {
    state = discovery.reason
  } else if (accounts.length === 0) {
    state = "connected_no_accounts"
  }

  return Response.json({ connectionId, state, discovery, accounts })
}
