import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadOwnedBrokerConnection } from "@/lib/integrations/brokerConnectionAccess"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { runTradovateAccountDiscovery } from "@/lib/integrations/tradovate/runTradovateAccountDiscovery"
import {
  mutateTradovateConnectionPendingLink,
  parseTradovatePendingLinkHttpBody,
} from "@/lib/integrations/tradovate/tradovateConnectionPendingLinkHttp"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = { params: Promise<{ connectionId: string }> }

export async function POST(req: Request, context: RouteContext) {
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

  let requestBody: Record<string, unknown> = {}
  try {
    const raw = await req.text()
    if (raw.trim()) {
      const parsed = JSON.parse(raw) as unknown
      if (parsed && typeof parsed === "object") {
        requestBody = parsed as Record<string, unknown>
      }
    }
  } catch {
    return Response.json({ error: "Invalid request." }, { status: 400 })
  }

  const nestedPending = parseTradovatePendingLinkHttpBody(
    requestBody.pendingTradetraxsLink
  )
  if (nestedPending?.action) {
    return mutateTradovateConnectionPendingLink(integrationDb, {
      userId: user.id,
      connectionId,
      body: nestedPending,
    })
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
