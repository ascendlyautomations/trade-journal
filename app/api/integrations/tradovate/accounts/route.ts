import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadTradovateAccountsForUser } from "@/lib/integrations/tradovate/runTradovateAccountDiscovery"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const url = new URL(req.url)
  const forceRefresh = url.searchParams.get("refresh") === "1"

  try {
    const payload = await loadTradovateAccountsForUser(supabaseServiceRole, user.id, {
      forceRefresh,
    })

    let state: string = "not_connected"
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
      state,
      connectionStatus: payload.connectionStatus,
      discovery: payload.discovery,
      accounts: payload.accounts,
    })
  } catch (err) {
    console.error(
      "[tradovate/accounts] load_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return Response.json({ error: "Could not load Tradovate accounts." }, { status: 500 })
  }
}
