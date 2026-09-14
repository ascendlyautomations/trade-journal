import { getRouteUser } from "@/app/api/_lib/getRouteUser"
import { loadSafeBrokerIntegration } from "@/lib/integrations/brokerIntegrationConnection"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    const status = await loadSafeBrokerIntegration(supabaseServiceRole, {
      userId: user.id,
      provider: "tradovate",
    })
    return Response.json(status)
  } catch (err) {
    console.error(
      "[tradovate/status] load_failed",
      err instanceof Error ? err.message : "unknown"
    )
    return Response.json({ error: "Could not load integration status." }, { status: 500 })
  }
}
