/** Free tier limits per UTC calendar day (Pro unlimited). */

export const FREE_PLAN_DAILY_TRADE_LIMIT = 3

export const FREE_PLAN_DAILY_POST_LIMIT = 3

export const FREE_PLAN_DAILY_CLIP_LIMIT = 3

export type FreePlanDailyLimitKind = "trade" | "post" | "clip"

export function formatFreePlanDailyLimitMessage(
  limit: number,
  resource: "trade" | "post" | "clip"
): string {
  const label = limit === 1 ? resource : `${resource}s`
  return `You've reached the Free plan limit of ${limit} ${label} every 24 hours.`
}

export const FREE_PLAN_DAILY_TRADE_LIMIT_MESSAGE = formatFreePlanDailyLimitMessage(
  FREE_PLAN_DAILY_TRADE_LIMIT,
  "trade"
)

export const FREE_PLAN_DAILY_POST_LIMIT_MESSAGE = formatFreePlanDailyLimitMessage(
  FREE_PLAN_DAILY_POST_LIMIT,
  "post"
)

export const FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE = formatFreePlanDailyLimitMessage(
  FREE_PLAN_DAILY_CLIP_LIMIT,
  "clip"
)

/** Modal / upgrade prompt copy with Pro upsell. */
export const FREE_PLAN_DAILY_TRADE_LIMIT_UPGRADE_MESSAGE = `${FREE_PLAN_DAILY_TRADE_LIMIT_MESSAGE}\n\nUpgrade to TradeTraxs Pro for unlimited trade journaling.`

export const FREE_PLAN_DAILY_POST_LIMIT_UPGRADE_MESSAGE = `${FREE_PLAN_DAILY_POST_LIMIT_MESSAGE}\n\nUpgrade to TradeTraxs Pro for unlimited posting.`

export const FREE_PLAN_DAILY_CLIP_LIMIT_UPGRADE_MESSAGE = `${FREE_PLAN_DAILY_CLIP_LIMIT_MESSAGE}\n\nUpgrade to TradeTraxs Pro for unlimited clips.`

/** Pricing surfaces — e.g. "3 Trades / day". */
export function formatFreePlanDailyLimitPricingLabel(
  limit: number,
  resource: "Trade" | "Post" | "Clip"
): string {
  const plural = limit === 1 ? resource : `${resource}s`
  return `${limit} ${plural} / day`
}

export const FREE_PLAN_DAILY_TRADE_PRICING_LABEL = formatFreePlanDailyLimitPricingLabel(
  FREE_PLAN_DAILY_TRADE_LIMIT,
  "Trade"
)

export const FREE_PLAN_DAILY_POST_PRICING_LABEL = formatFreePlanDailyLimitPricingLabel(
  FREE_PLAN_DAILY_POST_LIMIT,
  "Post"
)

export const FREE_PLAN_DAILY_CLIP_PRICING_LABEL = formatFreePlanDailyLimitPricingLabel(
  FREE_PLAN_DAILY_CLIP_LIMIT,
  "Clip"
)

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

/** Detect known free-plan daily limit violations from Supabase/Postgres errors. */
export function parseFreePlanDailyLimitError(
  error: unknown
): FreePlanDailyLimitKind | null {
  const blob = errorBlob(error)
  if (!blob) return null

  if (
    blob.includes("free_plan_daily_trade_limit") ||
    (blob.includes("trade") &&
      (blob.includes("per day") ||
        blob.includes("per 24 hours") ||
        blob.includes("every 24 hours")) &&
      (blob.includes("limit") || blob.includes("allows only")))
  ) {
    return "trade"
  }

  if (
    blob.includes("free_plan_daily_post_limit") ||
    (blob.includes("post") &&
      (blob.includes("per day") ||
        blob.includes("per 24 hours") ||
        blob.includes("every 24 hours")) &&
      (blob.includes("limit") || blob.includes("allows only")))
  ) {
    return "post"
  }

  if (
    blob.includes("free_plan_daily_clip_limit") ||
    blob.includes("free_plan_reels_limit") ||
    ((blob.includes("clip") || blob.includes("reel")) &&
      (blob.includes("per day") ||
        blob.includes("per 24 hours") ||
        blob.includes("every 24 hours")) &&
      (blob.includes("limit") || blob.includes("allows only")))
  ) {
    return "clip"
  }

  return null
}
