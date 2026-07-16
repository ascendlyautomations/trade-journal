/**
 * Public account privacy — hide unique account identifiers from non-owners
 * while preserving account-type badges (Live, Funded, Evaluation, etc.).
 */

/** Unique / user-specific account fields — never expose to other viewers. */
export const TRADE_ACCOUNT_IDENTIFIER_KEYS = [
  "account_name",
  "account_id",
  "account_number",
  "locked_account_name",
  "locked_account_number",
  "locked_account_id",
  "source_account_id",
] as const

/** Additional trade fields that reveal account sizing / labels to the public. */
export const TRADE_ACCOUNT_PUBLIC_STRIP_KEYS = [
  ...TRADE_ACCOUNT_IDENTIFIER_KEYS,
  "account_size",
] as const

/**
 * Trade columns safe for non-owner SELECT (no account_name, account_id, account_size).
 * Includes fields needed for public cards, feed, profile analytics, and modals.
 */
export const PUBLIC_TRADE_SELECT = [
  "id",
  "user_id",
  "created_at",
  "date",
  "trade_date",
  "pnl",
  "rr",
  "points",
  "contracts",
  "session",
  "ticker",
  "direction",
  "strategy",
  "trade_type",
  "notes",
  "public_description",
  "is_public",
  "is_pinned",
  "image_url",
  "entry_time",
  "exit_time",
  "entry_price",
  "exit_price",
  "duration_seconds",
  "duration_text",
  "account_type",
  "mode",
  "confidence",
  "emotion",
  "followed_plan",
  "mistake_type",
  "market_condition",
  "timeframe",
  "news_event",
  "psychology_notes",
  "reviewed",
  "trade_mode",
  "copied_account_ids",
  "copy_trading_group_id",
].join(", ")

/** Owner trade columns for app cache (dashboard, trades, calendar, analyst). */
export const TRADES_APP_SELECT = [
  PUBLIC_TRADE_SELECT,
  "account_name",
  "account_id",
  "account_size",
  "account_category",
  "top_confluences",
  "is_initial_import",
  "source_account_id",
].join(", ")

export function tradeSelectForViewer(isOwner: boolean): string {
  return isOwner ? TRADES_APP_SELECT : PUBLIC_TRADE_SELECT
}

/** Human-readable badge label from account_type / mode only (never account_name). */
export function formatPublicAccountTypeLabel(
  raw: string | null | undefined
): string | null {
  const norm = String(raw ?? "")
    .trim()
    .toLowerCase()
  if (!norm || norm === "imported") return null
  if (norm === "live") return "Live"
  if (norm === "eval" || norm === "evaluation") return "Evaluation"
  if (norm === "funded") return "Funded"
  if (norm === "backtest") return "Backtest"
  if (norm === "personal") return "Personal"
  if (norm === "sim") return "Sim"
  if (norm === "broker") return "Broker"
  if (norm === "prop firm" || norm === "prop_firm" || norm === "propfirm") {
    return "Prop Firm"
  }
  return norm.charAt(0).toUpperCase() + norm.slice(1)
}

export function publicAccountBadgeFromTrade(trade: {
  account_type?: string | null
  mode?: string | null
}): string | null {
  return formatPublicAccountTypeLabel(trade.account_type ?? trade.mode)
}

export function sanitizeTradeForViewer<T extends Record<string, unknown>>(
  trade: T | null | undefined,
  options: { isOwner: boolean }
): T | null | undefined {
  if (!trade || options.isOwner) return trade
  const out = { ...trade } as T
  for (const key of TRADE_ACCOUNT_PUBLIC_STRIP_KEYS) {
    delete (out as Record<string, unknown>)[key]
  }
  return out
}

export function sanitizeTradesForViewer<T extends Record<string, unknown>>(
  trades: T[],
  options: { isOwner: boolean }
): T[] {
  if (options.isOwner) return trades
  return trades.map((t) => sanitizeTradeForViewer(t, options) as T)
}
