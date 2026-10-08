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

export const TRADETRAXS_PRO_DISPLAY_NAME = "TraxPro"

export function proGateSubtitle(reason: ProGateReason): string {
  switch (reason.type) {
    case "limit":
      switch (reason.limit) {
        case "account_count":
          return "You've reached your Free plan limit of 3 trading accounts total."
        case "daily_trades":
          return "This action is included on the Free plan."
        case "daily_posts":
          return "This action is included on the Free plan."
        case "daily_clips":
          return "You've reached the Free plan limit of 4 Clips per UTC calendar day."
        case "daily_direct_messages":
          return "Direct messaging is included on the Free plan."
        case "csv_import_cooldown":
          return "CSV import is included on the Free plan."
      }
      break
    case "feature":
      switch (reason.feature) {
        case "ai_analyst":
          return "AI Trade Analyst is available with TraxPro."
        case "backtest_lab":
          return "Backtest Lab is available with TraxPro."
        case "prop_firm":
          return "Advanced Prop Firm Analytics are available with TraxPro."
        case "copy_trading":
          return "Copy Trading is available with TraxPro."
        case "premium_analytics":
          return "Advanced performance analytics are available with TraxPro."
        case "trading_reports":
          return "Trading reports are available with TraxPro."
        case "performance_exports":
          return "Performance exports are available with TraxPro."
        case "generic":
          return "This feature is available with TraxPro."
      }
  }
  return "This feature is available with TraxPro."
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
  const head = code.trim().split(":")[0]?.trim().toUpperCase() ?? ""
  if (head === "TRAXPRO_COPY_TRADING_REQUIRED") {
    return { type: "feature", feature: "copy_trading" }
  }
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
