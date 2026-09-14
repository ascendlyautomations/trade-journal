import type { SupabaseClient } from "@supabase/supabase-js"
import { getRouteUser, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { disconnectBrokerIntegrationById } from "@/lib/integrations/brokerIntegrationConnection"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const integrationDb = supabaseServiceRole as SupabaseClient

type RouteContext = { params: Promise<{ connectionId: string }> }

export async function POST(_req: Request, context: RouteContext) {
  const user = await getRouteUser(_req)
  if (!user?.id) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  const { connectionId } = await context.params

  try {
    const disconnected = await disconnectBrokerIntegrationById(integrationDb, {
      userId: user.id,
      connectionId,
      provider: "tradovate",
    })
    return Response.json({ ok: true, disconnected })
  } catch (err) {
    console.error(
      "[tradovate/connections/disconnect] failed",
      err instanceof Error ? err.message : "unknown"
    )
    return Response.json({ error: "Could not disconnect Tradovate." }, { status: 500 })
  }
}
