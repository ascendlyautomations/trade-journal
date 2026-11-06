import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitOutboxProcessorAuthorized } from "@/lib/livekit/outboxProcessorAuth.ts"
import { processLiveKitBroadcastDisconnectChecks } from "@/lib/livekit/processBroadcastDisconnectChecks.ts"

export const runtime = "nodejs"
export const maxDuration = 60
export const dynamic = "force-dynamic"

type Body = {
  roomId?: string
  sessionId?: string
  source?: string
}

function parseBody(raw: unknown): Body {
  if (!raw || typeof raw !== "object") return {}
  const b = raw as Record<string, unknown>
  const roomId = typeof b.roomId === "string" ? b.roomId.trim() : undefined
  const sessionId =
    typeof b.sessionId === "string" ? b.sessionId.trim() : undefined
  const source = typeof b.source === "string" ? b.source.trim() : undefined
  return {
    roomId: roomId || undefined,
    sessionId: sessionId || undefined,
    source,
  }
}

/** Secured processor for Supabase pg_cron (and optional manual ops). */
export async function POST(req: Request) {
  if (!isLiveKitOutboxProcessorAuthorized(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  let body: Body = {}
  try {
    const raw = await req.text()
    if (raw.trim()) {
      body = parseBody(JSON.parse(raw))
    }
  } catch {
    return Response.json({ error: "Invalid JSON body." }, { status: 400 })
  }

  try {
    const result = await processLiveKitBroadcastDisconnectChecks(
      supabaseServiceRole,
      {
        roomId: body.roomId,
        sessionId: body.sessionId,
        limit: body.roomId || body.sessionId ? 5 : 30,
      }
    )
    return Response.json({ ok: true, ...result, source: body.source ?? null })
  } catch (err) {
    console.error("[internal/livekit/process-broadcast-disconnect]", err)
    return Response.json(
      { error: "Broadcast disconnect processing failed." },
      { status: 500 }
    )
  }
}

export async function GET(req: Request) {
  return POST(req)
}
