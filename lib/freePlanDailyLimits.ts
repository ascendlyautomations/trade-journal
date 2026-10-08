/** Free tier Clips cap per UTC calendar day (TraxPro unlimited). */

export const FREE_PLAN_DAILY_CLIP_LIMIT = 4

export type FreePlanDailyLimitKind = "clip"

export function formatFreePlanDailyClipLimitMessage(limit: number): string {
  const label = limit === 1 ? "Clip" : "Clips"
  return `You've reached the Free plan limit of ${limit} ${label} per UTC calendar day.`
}

export const FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE = formatFreePlanDailyClipLimitMessage(
  FREE_PLAN_DAILY_CLIP_LIMIT
)

export const FREE_PLAN_DAILY_CLIP_LIMIT_UPGRADE_MESSAGE = `${FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE}\n\nUpgrade to TraxPro for unlimited Clips.`

export function formatFreePlanDailyClipPricingLabel(
  limit = FREE_PLAN_DAILY_CLIP_LIMIT
): string {
  const label = limit === 1 ? "Clip" : "Clips"
  return `${limit} ${label} / day`
}

export const FREE_PLAN_DAILY_CLIP_PRICING_LABEL =
  formatFreePlanDailyClipPricingLabel()

export const FREE_PLAN_UNLIMITED_MANUAL_TRADES_LABEL = "Unlimited manual trade entries"
export const FREE_PLAN_UNLIMITED_POSTS_LABEL = "Unlimited posts"
export const FREE_PLAN_ACTIVE_TRADING_ACCOUNTS_LABEL =
  "Up to 3 trading accounts (choose which receive new trades after TraxPro)"
export const FREE_PLAN_UNLIMITED_CSV_IMPORTS_LABEL = "Unlimited CSV imports"
export const FREE_PLAN_BROKER_INTEGRATIONS_LABEL =
  "Broker integrations (Tradovate, Rithmic, and supported connections)"

type SupabaseErrorShape = {
  message?: string
  code?: string
  hint?: string
  details?: string
}

function errorBlob(error: unknown): string {
  const e = error as SupabaseErrorShape | null | undefined
  if (!e) return ""
  return [e.message, e.hint, e.details, e.code].filter(Boolean).join(" ").toLowerCase()
}

/** Detect Free-plan daily Clip limit violations from Supabase/Postgres errors. */
export function parseFreePlanDailyLimitError(
  error: unknown
): FreePlanDailyLimitKind | null {
  const blob = errorBlob(error)
  if (!blob) return null

  if (
    blob.includes("free_plan_daily_clip_limit") ||
    blob.includes("free_plan_reels_limit") ||
    ((blob.includes("clip") || blob.includes("reel")) &&
      (blob.includes("per utc") ||
        blob.includes("per day") ||
        blob.includes("calendar day")) &&
      (blob.includes("limit") || blob.includes("allows only")))
  ) {
    return "clip"
  }

  return null
}
