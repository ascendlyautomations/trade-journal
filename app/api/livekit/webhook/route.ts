import { after } from "next/server"
import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { handleLiveKitWebhookForBroadcast } from "@/lib/livekit/processLiveKitWebhook.ts"
import {
  BROADCAST_DISCONNECT_GRACE_MS,
  processBroadcasterDisconnectChecks,
} from "@/lib/livekit/tradeRoomBroadcastDisconnectCheck.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

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

  if (result.deferredDisconnectCheck) {
    const { roomId, sessionId } = result.deferredDisconnectCheck
    after(async () => {
      await sleep(BROADCAST_DISCONNECT_GRACE_MS)
      await processBroadcasterDisconnectChecks(supabaseServiceRole, {
        roomId,
        sessionId,
        limit: 1,
      })
    })
  }

  return Response.json({ ok: true, handled: result.handled })
}
