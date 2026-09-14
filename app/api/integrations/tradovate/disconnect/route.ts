import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { disconnectBrokerIntegration } from "@/lib/integrations/brokerIntegrationConnection"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function POST(req: Request) {
  const user = await getRouteUser(req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    const disconnected = await disconnectBrokerIntegration(supabaseServiceRole, {
      userId: user.id,
      provider: "tradovate",
    })
    return Response.json({ ok: true, disconnected })
  } catch (err) {
    console.error(
      "[tradovate/disconnect] failed",
      err instanceof Error ? err.message : "unknown"
    )
    return Response.json({ error: "Could not disconnect Tradovate." }, { status: 500 })
  }
}
