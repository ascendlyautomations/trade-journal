import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { attachSyncViewsToBrokerAccounts } from "@/lib/integrations/tradovate/runTradovateAccountTradeSync"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = {
  params: Promise<{ connectionId: string; mappingId: string }>
}

export async function PATCH(req: Request, context: RouteContext) {
  const user = await getRouteUser(req)
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

  let body: { enabled?: boolean }
  try {
    body = (await req.json()) as { enabled?: boolean }
  } catch {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }
  if (typeof body.enabled !== "boolean") {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  const { data: mapping } = await integrationDb
    .from("broker_integration_accounts")
    .select("id")
    .eq("id", mappingId)
    .eq("user_id", user.id)
    .eq("connection_id", connectionId)
    .maybeSingle()

  if (!mapping) {
    return Response.json({ error: "Broker account not found." }, { status: 404 })
  }

  const now = new Date().toISOString()
  const { error: upsertError } = await integrationDb
    .from("broker_integration_account_sync")
    .upsert(
      {
        broker_integration_account_id: mappingId,
        user_id: user.id,
        connection_id: connectionId,
        auto_sync_enabled: body.enabled,
        updated_at: now,
      },
      { onConflict: "broker_integration_account_id" }
    )

  if (upsertError) {
    return Response.json({ error: "Could not update automatic sync." }, { status: 500 })
  }

  const accounts = await listSafeBrokerIntegrationAccounts(integrationDb, {
    userId: user.id,
    provider: "tradovate",
    connectionId,
  })
  const accountsWithSync = await attachSyncViewsToBrokerAccounts(
    integrationDb,
    accounts
  )

  return Response.json({
    ok: true,
    connectionId,
    mappingId,
    autoSyncEnabled: body.enabled,
    accounts: accountsWithSync,
  })
}
