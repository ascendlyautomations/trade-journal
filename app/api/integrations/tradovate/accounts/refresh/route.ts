import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { listSafeBrokerIntegrationAccounts } from "@/lib/integrations/brokerIntegrationAccounts"
import { runTradovateAccountDiscovery } from "@/lib/integrations/tradovate/runTradovateAccountDiscovery"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const discovery = await runTradovateAccountDiscovery(supabaseServiceRole, user.id)
  const accounts = await listSafeBrokerIntegrationAccounts(supabaseServiceRole, {
    userId: user.id,
    provider: "tradovate",
  })

  let state = "connected"
  if (!discovery.ok) {
    state = discovery.reason
  } else if (accounts.length === 0) {
    state = "connected_no_accounts"
  }

  return Response.json({ state, discovery, accounts })
}
