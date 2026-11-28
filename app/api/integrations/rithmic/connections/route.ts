import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { listSafeBrokerConnections } from "@/lib/integrations/brokerIntegrationConnection"
import { isRithmicDevelopmentIntegrationEnabled } from "@/lib/integrations/rithmic/rithmicDevIntegration"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  if (!isRithmicDevelopmentIntegrationEnabled()) {
    return Response.json({
      provider: "rithmic",
      connectionCount: 0,
      connections: [],
    })
  }

  try {
    const connections = await listSafeBrokerConnections(supabaseServiceRole, {
      userId: user.id,
      provider: "rithmic",
    })
    return Response.json({
      provider: "rithmic",
      connectionCount: connections.length,
      connections,
    })
  } catch (err) {
    console.error(
      "[rithmic/connections] list_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return Response.json({ error: "Could not load Rithmic connections." }, { status: 500 })
  }
}
