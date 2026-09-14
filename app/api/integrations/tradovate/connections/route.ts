import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { listSafeBrokerConnections } from "@/lib/integrations/brokerIntegrationConnection"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    const connections = await listSafeBrokerConnections(supabaseServiceRole, {
      userId: user.id,
      provider: "tradovate",
    })
    return Response.json({
      provider: "tradovate",
      connectionCount: connections.length,
      connections,
    })
  } catch (err) {
    console.error(
      "[tradovate/connections] list_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return Response.json({ error: "Could not load Tradovate connections." }, { status: 500 })
  }
}
