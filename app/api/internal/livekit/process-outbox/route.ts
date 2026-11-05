import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitOutboxProcessorAuthorized } from "@/lib/livekit/outboxProcessorAuth.ts"
import { processLiveKitDisconnectOutbox } from "@/lib/livekit/processDisconnectOutbox.ts"

export const runtime = "nodejs"
export const maxDuration = 60
export const dynamic = "force-dynamic"

type Body = {
  outboxId?: string
  source?: string
}

function parseBody(raw: unknown): Body {
  if (!raw || typeof raw !== "object") return {}
  const b = raw as Record<string, unknown>
  const outboxId =
    typeof b.outboxId === "string" ? b.outboxId.trim() : undefined
  const source = typeof b.source === "string" ? b.source.trim() : undefined
  return { outboxId: outboxId || undefined, source }
}

/** Secured processor for Supabase pg_net (insert trigger) and pg_cron retries. */
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
    const result = await processLiveKitDisconnectOutbox(supabaseServiceRole, {
      outboxId: body.outboxId,
    })
    return Response.json({ ok: true, ...result, source: body.source ?? null })
  } catch (err) {
    console.error("[internal/livekit/process-outbox]", err)
    return Response.json({ error: "Outbox processing failed." }, { status: 500 })
  }
}

/** Manual / legacy invocations (same auth as POST). */
export async function GET(req: Request) {
  if (!isLiveKitOutboxProcessorAuthorized(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    const result = await processLiveKitDisconnectOutbox(supabaseServiceRole)
    return Response.json({ ok: true, ...result })
  } catch (err) {
    console.error("[internal/livekit/process-outbox]", err)
    return Response.json({ error: "Outbox processing failed." }, { status: 500 })
  }
}
