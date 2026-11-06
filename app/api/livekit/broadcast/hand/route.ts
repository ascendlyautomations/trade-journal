import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { parseRoomIdBody } from "../_shared.ts"
import {
  assertActiveBroadcastSession,
  isUserBlockedFromBroadcastSession,
  setBroadcastHandRaised,
} from "@/lib/livekit/tradeRoomBroadcastInteractiveState.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

function parseHandBody(
  raw: unknown
): { roomId: string; sessionId: string; raised: boolean } | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const sessionId = typeof b.sessionId === "string" ? b.sessionId.trim() : ""
  if (!roomId || !sessionId) return null
  if (typeof b.raised !== "boolean") return null
  return { roomId, sessionId, raised: b.raised }
}

export async function POST(req: Request) {
  const { user, authError } = await getRouteUserAuth(req)
  if (!user?.id) {
    return Response.json(
      { error: "Unauthorized", detail: authError?.code ?? null },
      { status: 401 }
    )
  }

  let body: unknown
  try {
    body = await req.json()
  } catch {
    return Response.json({ error: "Invalid JSON body." }, { status: 400 })
  }

  const parsed = parseHandBody(body)
  if (!parsed) {
    return Response.json(
      { error: "roomId, sessionId, and raised are required." },
      { status: 400 }
    )
  }

  const session = await assertActiveBroadcastSession(
    supabaseServiceRole,
    parsed.roomId,
    parsed.sessionId
  )
  if (!session.ok) {
    return Response.json({ error: session.error }, { status: session.status })
  }

  if (await isUserBlockedFromBroadcastSession(supabaseServiceRole, parsed.sessionId, user.id)) {
    return Response.json({ error: "You cannot join this stream." }, { status: 403 })
  }

  const result = await setBroadcastHandRaised(supabaseServiceRole, {
    sessionId: parsed.sessionId,
    userId: user.id,
    raised: parsed.raised,
  })

  if (!result.ok) {
    return Response.json({ error: result.error }, { status: result.status })
  }

  return Response.json({ ok: true })
}
