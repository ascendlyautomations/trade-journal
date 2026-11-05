import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"
import { isLiveKitOutboxProcessorAuthorized } from "@/lib/livekit/outboxProcessorAuth.ts"
import { processLiveKitDisconnectOutbox } from "@/lib/livekit/processDisconnectOutbox.ts"

export const runtime = "nodejs"
export const maxDuration = 60
export const dynamic = "force-dynamic"

/**
 * Legacy path for manual ops. Supabase pg_net / pg_cron should call
 * `/api/internal/livekit/process-outbox` instead (same Bearer secret).
 */
async function runProcessor(req: Request) {
  if (!isLiveKitOutboxProcessorAuthorized(req)) {
    return Response.json({ error: "Unauthorized" }, { status: 401 })
  }

  try {
    const result = await processLiveKitDisconnectOutbox(supabaseServiceRole)
    return Response.json({ ok: true, ...result })
  } catch (err) {
    console.error("[cron/livekit-disconnect-outbox]", err)
    return Response.json({ error: "Outbox processing failed." }, { status: 500 })
  }
}

export async function GET(req: Request) {
  return runProcessor(req)
}

export async function POST(req: Request) {
  return runProcessor(req)
}
