import { supabaseServiceRole } from "@/app/api/_lib/getRouteUser"

type WindowRule = {
  windowSeconds: number
  maxCount: number
}

export type DurableRateLimitAction =
  | "ai_analyze_trade"
  | "ai_psychology_coach"
  | "ai_screenshot_extract"

const RULES: Record<DurableRateLimitAction, WindowRule[]> = {
  ai_analyze_trade: [
    { windowSeconds: 60, maxCount: 20 },
    { windowSeconds: 3600, maxCount: 120 },
  ],
  ai_psychology_coach: [
    { windowSeconds: 60, maxCount: 20 },
    { windowSeconds: 3600, maxCount: 120 },
  ],
  ai_screenshot_extract: [
    { windowSeconds: 60, maxCount: 5 },
    { windowSeconds: 3600, maxCount: 20 },
  ],
}

function windowStartIso(now: Date, windowSeconds: number): string {
  const epochSec = Math.floor(now.getTime() / 1000)
  const floored = Math.floor(epochSec / windowSeconds) * windowSeconds
  return new Date(floored * 1000).toISOString()
}

function retryAfterSec(now: Date, windowSeconds: number): number {
  const epochSec = Math.floor(now.getTime() / 1000)
  const nextWindowStart = (Math.floor(epochSec / windowSeconds) + 1) * windowSeconds
  return Math.max(1, nextWindowStart - epochSec)
}

/**
 * Postgres-backed per-user rate limits for BFF routes (survives Vercel cold starts).
 * Uses existing `rate_limit_counters` rows keyed by BFF action names.
 */
export async function consumeDurableUserRateLimit(
  userId: string,
  action: DurableRateLimitAction
): Promise<{ allowed: true } | { allowed: false; retryAfterSec: number }> {
  const rules = RULES[action]
  const now = new Date()
  const db = supabaseServiceRole

  for (const rule of rules) {
    const windowStart = windowStartIso(now, rule.windowSeconds)

    const { data: existing, error: readError } = await db
      .from("rate_limit_counters")
      .select("count")
      .eq("user_id", userId)
      .eq("action", action)
      .eq("window_seconds", rule.windowSeconds)
      .eq("window_start", windowStart)
      .maybeSingle()

    if (readError) {
      console.error("[durableUserRateLimit] read failed", readError)
      return { allowed: false, retryAfterSec: 60 }
    }

    const nextCount = (existing?.count ?? 0) + 1
    if (nextCount > rule.maxCount) {
      return {
        allowed: false,
        retryAfterSec: retryAfterSec(now, rule.windowSeconds),
      }
    }

    const { error: writeError } = await db.from("rate_limit_counters").upsert(
      {
        user_id: userId,
        action,
        window_seconds: rule.windowSeconds,
        window_start: windowStart,
        count: nextCount,
      },
      { onConflict: "user_id,action,window_seconds,window_start" }
    )

    if (writeError) {
      console.error("[durableUserRateLimit] write failed", writeError)
      return { allowed: false, retryAfterSec: 60 }
    }
  }

  return { allowed: true }
}

export function rateLimitExceededResponse(retryAfterSec: number) {
  return Response.json(
    { error: "Slow down — try again in a moment." },
    {
      status: 429,
      headers: { "Retry-After": String(retryAfterSec) },
    }
  )
}
