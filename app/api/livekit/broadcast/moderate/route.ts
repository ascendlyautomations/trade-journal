import { getRouteUserAuth, supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import {
  executeBroadcastModeration,
  type BroadcastModerationAction,
} from "@/lib/livekit/tradeRoomBroadcastModeration.ts"

export const runtime = "nodejs"
export const dynamic = "force-dynamic"

const ALLOWED: BroadcastModerationAction[] = [
  "invite_speak",
  "request_unmute",
  "mute_speaker",
  "revoke_speaker",
  "remove_viewer",
  "dismiss_hand",
]

function parseBody(raw: unknown): {
  roomId: string
  sessionId: string
  targetUserId: string
  action: BroadcastModerationAction
  blockRejoin?: boolean
} | null {
  if (!raw || typeof raw !== "object") return null
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : ""
  const sessionId = typeof b.sessionId === "string" ? b.sessionId.trim() : ""
  const targetUserId = typeof b.targetUserId === "string" ? b.targetUserId.trim() : ""
  const action = typeof b.action === "string" ? b.action.trim() : ""
  if (!roomId || !sessionId || !targetUserId || !action) return null
  if (!ALLOWED.includes(action as BroadcastModerationAction)) return null
  return {
    roomId,
    sessionId,
    targetUserId,
    action: action as BroadcastModerationAction,
    blockRejoin: b.blockRejoin === true,
  }
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

  const parsed = parseBody(body)
  if (!parsed) {
    return Response.json({ error: "Invalid moderation request." }, { status: 400 })
  }

  const result = await executeBroadcastModeration(supabaseServiceRole, {
    actorUserId: user.id,
    roomId: parsed.roomId,
    sessionId: parsed.sessionId,
    targetUserId: parsed.targetUserId,
    action: parsed.action,
    blockRejoin: parsed.blockRejoin,
  })

  if (!result.ok) {
    return Response.json({ error: result.error }, { status: result.status })
  }

  return Response.json({
    ok: true,
    invitationId: result.invitationId ?? null,
    targetDisplayName: result.targetDisplayName ?? null,
  })
}
