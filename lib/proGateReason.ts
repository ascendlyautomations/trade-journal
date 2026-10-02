/**
 * Shared Pro gate semantics — web + server error contract.
 * User-facing copy uses "TradeTraxs Pro" branding.
 */

export const PRO_LIMIT_REACHED_CODE = "PRO_LIMIT_REACHED" as const

export type ProLimitKind =
  | "account_count"
  | "daily_trades"
  | "daily_posts"
  | "daily_clips"
  | "daily_direct_messages"
  | "csv_import_cooldown"

export type ProFeatureKind =
  | "ai_analyst"
  | "backtest_lab"
  | "prop_firm"
  | "copy_trading"
  | "premium_analytics"
  | "trading_reports"
  | "performance_exports"
  | "generic"

export type ProGateReason =
  | { type: "limit"; limit: ProLimitKind }
  | { type: "feature"; feature: ProFeatureKind }

export type ProLimitPayload = {
  code: typeof PRO_LIMIT_REACHED_CODE
  limit: ProLimitKind
  message: string
}

export const TRADETRAXS_PRO_DISPLAY_NAME = "TradeTraxs Pro"

export function proGateSubtitle(reason: ProGateReason): string {
  switch (reason.type) {
    case "limit":
      switch (reason.limit) {
        case "account_count":
          return "You've reached your Free plan limit of 3 trading accounts."
        case "daily_trades":
          return "You've used your 3 Free trades for today."
        case "daily_posts":
          return "You've used your 3 Free posts for today."
        case "daily_clips":
          return "You've used your 3 Free clips for today."
        case "daily_direct_messages":
          return "You've reached the Free plan limit of 25 direct messages in 24 hours."
        case "csv_import_cooldown":
          return "Free accounts can import a CSV once every 3 days."
      }
      break
    case "feature":
      switch (reason.feature) {
        case "ai_analyst":
          return "AI Analyst is available with TradeTraxs Pro."
        case "backtest_lab":
          return "Backtest Lab is available with TradeTraxs Pro."
        case "prop_firm":
          return "Prop Firm Mode is available with TradeTraxs Pro."
        case "copy_trading":
          return "Copy Trading is available with TradeTraxs Pro."
        case "premium_analytics":
          return "Premium analytics are available with TradeTraxs Pro."
        case "trading_reports":
          return "Weekly and monthly trading reports are available with TradeTraxs Pro."
        case "performance_exports":
          return "Performance exports are available with TradeTraxs Pro."
        case "generic":
          return "This feature is available with TradeTraxs Pro."
      }
  }
  return "This feature is available with TradeTraxs Pro."
}

const LEGACY_LIMIT_MAP: Record<string, ProLimitKind> = {
  FREE_PLAN_ACCOUNT_LIMIT: "account_count",
  FREE_PLAN_DAILY_TRADE_LIMIT: "daily_trades",
  FREE_PLAN_DAILY_POST_LIMIT: "daily_posts",
  FREE_PLAN_DAILY_CLIP_LIMIT: "daily_clips",
  FREE_PLAN_REELS_LIMIT: "daily_clips",
  FREE_PLAN_DAILY_DM_LIMIT: "daily_direct_messages",
}

/** Map Postgres / legacy exception tokens to structured limits. */
export function proLimitKindFromLegacyCode(code: string): ProLimitKind | null {
  const head = code.trim().split(":")[0]?.trim().toUpperCase() ?? ""
  if (head in LEGACY_LIMIT_MAP) {
    return LEGACY_LIMIT_MAP[head as keyof typeof LEGACY_LIMIT_MAP]
  }
  return null
}

export function proGateReasonFromLegacyError(code: string): ProGateReason | null {
  const limit = proLimitKindFromLegacyCode(code)
  if (limit) return { type: "limit", limit }
  return null
}

export function proLimitKindFromError(error: unknown): ProLimitKind | null {
  return parseProLimitPayload(error)?.limit ?? null
}

export function isProLimitResponseBody(
  body: unknown
): body is ProLimitPayload {
  if (!body || typeof body !== "object") return false
  const row = body as { code?: string; limit?: string }
  return row.code === PRO_LIMIT_REACHED_CODE && typeof row.limit === "string"
}

export function buildProLimitPayload(limit: ProLimitKind): ProLimitPayload {
  const reason: ProGateReason = { type: "limit", limit }
  return {
    code: PRO_LIMIT_REACHED_CODE,
    limit,
    message: proGateSubtitle(reason),
  }
}

type ErrorLike = {
  message?: string
  code?: string
  error?: string
  limit?: string
}

/** Parse API/PostgREST payloads and legacy FREE_PLAN_* strings. */
export function parseProLimitPayload(error: unknown): ProLimitPayload | null {
  if (!error || typeof error !== "object") {
    if (typeof error === "string") {
      const legacy = proGateReasonFromLegacyError(error)
      if (legacy?.type === "limit") {
        return buildProLimitPayload(legacy.limit)
      }
    }
    return null
  }

  const row = error as ErrorLike
  const code = String(row.code ?? row.error ?? "").trim()
  if (code === PRO_LIMIT_REACHED_CODE) {
    const limitRaw = String(row.limit ?? "").trim() as ProLimitKind
    const known: ProLimitKind[] = [
      "account_count",
      "daily_trades",
      "daily_posts",
      "daily_clips",
      "daily_direct_messages",
      "csv_import_cooldown",
    ]
    if (known.includes(limitRaw)) {
      return {
        code: PRO_LIMIT_REACHED_CODE,
        limit: limitRaw,
        message:
          typeof row.message === "string" && row.message.trim()
            ? row.message.trim()
            : proGateSubtitle({ type: "limit", limit: limitRaw }),
      }
    }
  }

  const message = String(row.message ?? "").trim()
  if (message) {
    const legacy = proGateReasonFromLegacyError(message)
    if (legacy?.type === "limit") {
      return buildProLimitPayload(legacy.limit)
    }
    const upper = message.toUpperCase()
    const fromUpper = proLimitKindFromLegacyCode(upper)
    if (fromUpper) return buildProLimitPayload(fromUpper)
    if (upper.includes("CSV") && (upper.includes("IMPORT") || upper.includes("COOLDOWN"))) {
      return buildProLimitPayload("csv_import_cooldown")
    }
  }

  return null
}
