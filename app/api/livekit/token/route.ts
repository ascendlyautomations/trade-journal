import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { mintLiveKitVoiceToken } from "@/lib/livekit/mintLiveKitToken.ts"
import { isLiveKitConfigured } from "@/lib/livekit/config.ts"
import { resolveTradeRoomLiveVoiceAccess } from "@/lib/livekit/tradeRoomLiveVoiceAccess.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

type ParsedTokenRequestBody = {
  roomId: string
  sectionId: string
}

function parseTokenRequestBody(raw: unknown): ParsedTokenRequestBody | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const sectionId = typeof b.sectionId === "string" ? b.sectionId.trim() : ""
  if (!roomId || !sectionId) return null
  return { roomId, sectionId }
}

export async function POST(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json(
      { error: "Unauthorized", detail: authError?.code ?? null },
      { status: 401 }
    )
  }

  if (!isLiveKitConfigured()) {
    return Response.json(
      { error: "Live voice is not configured on the server." },
      { status: 503 }
    )
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: "Invalid JSON body." }, { status: 400 })
  }

  const parsed = parseTokenRequestBody(body)
  if (parsed === null) {
    return Response.json(
      { error: "roomId and sectionId are required." },
      { status: 400 }
    )
  }

  const { roomId, sectionId } = parsed

  const access = await resolveTradeRoomLiveVoiceAccess(supabaseServiceRole, {
    userId: user.id,
    roomId,
    sectionId,
  })

  if (!access.ok) {
    return Response.json({ error: access.error }, { status: access.status })
  }

  const session = await mintLiveKitVoiceToken(user.id, access)
  if (!session) {
    return Response.json(
      { error: "Could not mint LiveKit token." },
      { status: 503 }
    )
  }

  return Response.json(session)
}
