import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { loadBroadcastInteractiveSnapshot } from "@/lib/livekit/tradeRoomBroadcastInteractiveState.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

export async function GET(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json(
      { error: "Unauthorized", detail: authError?.code ?? null },
      { status: 401 }
    )
  }

  const url = new URL(req.url)
  const roomId = url.searchParams.get("roomId")?.trim() ?? ""
  if (!roomId) {
    return Response.json({ error: "roomId is required." }, { status: 400 })
  }

  const loaded = await loadBroadcastInteractiveSnapshot(supabaseServiceRole, {
    roomId,
    viewerUserId: user.id,
  })

  if (!loaded.ok) {
    return Response.json({ error: loaded.error }, { status: loaded.status })
  }

  return Response.json({
    snapshot: loaded.snapshot,
    profiles: loaded.profiles,
  })
}
