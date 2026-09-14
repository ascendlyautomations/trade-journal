import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { loadTradovateConnectionAccounts } from "@/lib/integrations/tradovate/runTradovateAccountDiscovery"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = { params: Promise<{ connectionId: string }> }

export async function GET(req: Request, context: RouteContext) {
  const user = await getRouteUser(req)
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

  const url = new URL(req.url)
  const forceRefresh = url.searchParams.get("refresh") === "1"

  try {
    const payload = await loadTradovateConnectionAccounts(
      integrationDb,
      user.id,
      connectionId,
      { forceRefresh }
    )

    let state = "not_connected"
    if (payload.connectionStatus === "connected") {
      if (payload.discovery?.ok === false) {
        state = payload.discovery.reason
      } else if (payload.accounts.length === 0) {
        state = "connected_no_accounts"
      } else {
        state = "connected"
      }
    } else if (payload.connectionStatus === "reconnect_required") {
      state = "reconnect_required"
    }

    return Response.json({
      connectionId,
      state,
      connectionStatus: payload.connectionStatus,
      discovery: payload.discovery,
      accounts: payload.accounts,
    })
  } catch (err) {
    console.error(
      "[tradovate/connections/accounts] load_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return Response.json({ error: "Could not load Tradovate accounts." }, { status: 500 })
  }
}
