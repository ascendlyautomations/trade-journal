/** Free tier: private direct messages sent per rolling 24-hour window. */

export const FREE_PLAN_DAILY_DM_LIMIT = 25

export const FREE_PLAN_DAILY_DM_LIMIT_TITLE = "Direct Message Limit Reached"

export const FREE_PLAN_DAILY_DM_LIMIT_MESSAGE =
  "You've reached your maximum daily messaging limit of 25/day on the Free plan.\n\nYou've reached the Free plan limit of 25 direct messages every 24 hours.\n\nUpgrade to Trader or wait until your limit resets."

/** Pricing surfaces — e.g. "25 Direct Messages / day". */
export const FREE_PLAN_DAILY_DM_PRICING_LABEL = "25 Direct Messages / day"

export const FREE_PLAN_UNLIMITED_TRADE_ROOM_MESSAGES_PRICING_LABEL =
  "Unlimited Trade Room Messages"

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

export function isFreePlanDailyDmLimitError(error: unknown): boolean {
  const blob = errorBlob(error)
  if (!blob) return false

  return (
    blob.includes("free_plan_daily_dm_limit") ||
    (blob.includes("direct message") &&
      blob.includes("25") &&
      (blob.includes("24 hour") || blob.includes("every 24 hours") || blob.includes("limit")))
  )
}
