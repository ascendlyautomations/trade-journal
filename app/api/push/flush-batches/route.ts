import { flushAllDuePushBatches } from "@/lib/server/push/pushBatching"

export const runtime = "nodejs"
/** Allow enough time to flush a batch of due windows. */
export const maxDuration = 60

/**
 * Safety-net flush for like/follow/room digest windows.
 * Protected by CRON_SECRET when set; also usable from authenticated ops.
 * Vercel Cron should hit this every minute (see vercel.json).
 */
export async function POST(req: Request) {
  const cronSecret = process.env.CRON_SECRET?.trim()
  if (cronSecret) {
    const auth = req.headers.get("authorization") || ""
    if (auth !== `Bearer ${cronSecret}`) {
      return Response.json({ error: "Unauthorized" }, { status: 401 })
    }
  }

  const flushed = await flushAllDuePushBatches()
  if (flushed > 0) {
    console.info("[push-batch] flush-batches completed", { flushed })
  }
  return Response.json({ ok: true, flushed })
}

export async function GET(req: Request) {
  return POST(req)
}
