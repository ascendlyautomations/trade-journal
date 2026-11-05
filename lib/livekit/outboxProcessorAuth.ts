/** Shared secret auth for LiveKit outbox processor (Supabase pg_net / pg_cron / manual). */
export function isLiveKitOutboxProcessorAuthorized(req: Request): boolean {
  const secret =
    process.env.LIVEKIT_OUTBOX_WEBHOOK_SECRET?.trim() ||
    process.env.CRON_SECRET?.trim()
  if (!secret) return false
  const auth = req.headers.get("authorization") ?? ""
  return auth === `Bearer ${secret}`
}
