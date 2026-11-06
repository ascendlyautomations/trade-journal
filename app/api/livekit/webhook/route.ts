import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { handleLiveKitWebhookForBroadcast } from "@/lib/livekit/processLiveKitWebhook.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function POST(req: Request) {
  const rawBody = await req.text()
  const authorizationHeader = req.headers.get("Authorization")

  const result = await handleLiveKitWebhookForBroadcast(
    supabaseServiceRole,
    rawBody,
    authorizationHeader
  )

  if (!result.ok) {
    return Response.json({ error: result.error }, { status: result.status })
  }

  return Response.json({ ok: true, handled: result.handled })
}
