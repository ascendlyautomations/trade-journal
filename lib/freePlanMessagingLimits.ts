/** Free tier: unlimited direct messages (Trade Room messaging also unlimited). */

export const FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL =
  "Unlimited direct messages"

export const FREE_PLAN_UNLIMITED_TRADE_ROOM_MESSAGES_PRICING_LABEL =
  "Unlimited Trade Room messages"

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

/** @deprecated Free plan no longer caps DMs — returns false for all errors. */
export function isFreePlanDailyDmLimitError(_error: unknown): boolean {
  return false
}

/** @deprecated */
export const FREE_PLAN_DAILY_DM_LIMIT = 0

/** @deprecated */
export const FREE_PLAN_DAILY_DM_LIMIT_TITLE = "Direct Message Limit Reached"

/** @deprecated */
export const FREE_PLAN_DAILY_DM_LIMIT_MESSAGE = ""

/** @deprecated Use FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL. */
export const FREE_PLAN_DAILY_DM_PRICING_LABEL =
  FREE_PLAN_UNLIMITED_DIRECT_MESSAGES_PRICING_LABEL
