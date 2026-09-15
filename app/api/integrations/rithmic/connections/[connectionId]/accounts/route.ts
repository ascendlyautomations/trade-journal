import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { loadRithmicConnectionAccounts } from "@/lib/integrations/rithmic/loadRithmicConnectionAccounts"

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
    provider: "rithmic",
  })
  if (!owned) {
    return Response.json({ error: "Connection not found." }, { status: 404 })
  }

  try {
    const payload = await loadRithmicConnectionAccounts(
      integrationDb,
      user.id,
      connectionId
    )

    let state = "not_connected"
    if (payload.connectionStatus === "connected") {
      state = payload.accounts.length === 0 ? "connected_no_accounts" : "connected"
    } else if (payload.connectionStatus === "reconnect_required") {
      state = "reconnect_required"
    }

    return Response.json({
      connectionId,
      state,
      connectionStatus: payload.connectionStatus,
      accounts: payload.accounts,
    })
  } catch (err) {
    console.error(
      "[rithmic/connections/accounts] load_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return Response.json({ error: "Could not load Rithmic accounts." }, { status: 500 })
  }
}
