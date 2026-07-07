/** Free tier: manual trades created per UTC calendar day. */
export const FREE_PLAN_DAILY_TRADE_LIMIT = 3

/** Free tier: feed + profile posts created per UTC calendar day. */
export const FREE_PLAN_DAILY_POST_LIMIT = 3

export const FREE_PLAN_DAILY_TRADE_LIMIT_MESSAGE =
  "Free members can add up to 3 trades per day.\n\nUpgrade to TradeTraxs Pro for unlimited trade journaling."

export const FREE_PLAN_DAILY_POST_LIMIT_MESSAGE =
  "Free members can publish up to 3 posts per day.\n\nUpgrade to TradeTraxs Pro for unlimited posting."

export type FreePlanDailyLimitKind = "trade" | "post"

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
      (blob.includes("per day") || blob.includes("per 24 hours")) &&
      (blob.includes("limit") || blob.includes("allows only")))
  ) {
    return "trade"
  }

  if (
    blob.includes("free_plan_daily_post_limit") ||
    (blob.includes("post") &&
      (blob.includes("per day") || blob.includes("per 24 hours")) &&
      (blob.includes("limit") || blob.includes("allows only")))
  ) {
    return "post"
  }

  return null
}
