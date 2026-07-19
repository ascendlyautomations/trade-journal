/** Trade Mode (journal classification) — distinct from account Eval/Funded mode. */

export const TRADE_MODE_VALUES = [
  "live",
  "sim",
  "replay",
  "backtest",
  "copy_traded",
] as const

export type TradeMode = (typeof TRADE_MODE_VALUES)[number]

export const TRADE_MODE_OPTIONS: { value: TradeMode; label: string }[] = [
  { value: "live", label: "Live" },
  { value: "sim", label: "SIM" },
  { value: "replay", label: "Replay" },
  { value: "backtest", label: "Backtest" },
  { value: "copy_traded", label: "Copy Traded" },
]

/**
 * Journal trade mode derived from the selected account — never user-selected.
 * Prop firm Eval/Funded and personal/broker Live accounts journal as "live";
 * Sim accounts as "sim"; Backtest accounts as "backtest". Copy Traded is
 * stamped by the copy-trading insert paths, not derived here.
 */
export function deriveTradeModeFromAccount(
  account: {
    mode?: unknown
    category?: unknown
  } | null | undefined
): TradeMode {
  const mode = String(account?.mode ?? "").trim().toLowerCase()
  const category = String(account?.category ?? "").trim().toLowerCase()
  if (category === "backtest" || mode === "backtest") return "backtest"
  if (mode === "sim") return "sim"
  if (mode === "replay") return "replay"
  return "live"
}

export function normalizeTradeMode(value: unknown): TradeMode | null {
  const raw = String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_")
  if (raw === "copy traded") return "copy_traded"
  if ((TRADE_MODE_VALUES as readonly string[]).includes(raw)) {
    return raw as TradeMode
  }
  return null
}

export function formatTradeModeLabel(mode: TradeMode | null | undefined): string {
  if (!mode) return "—"
  const found = TRADE_MODE_OPTIONS.find((o) => o.value === mode)
  return found?.label ?? mode
}

/** Destination count for Copy Traded ×N (never stored separately). */
export function getCopiedAccountCount(
  trade: { copied_account_ids?: unknown } | null | undefined
): number {
  const ids = trade?.copied_account_ids
  if (!Array.isArray(ids)) return 0
  return ids
    .map((id) => String(id ?? "").trim())
    .filter((id) => id.length > 0).length
}

export function isCopyTradedMode(
  trade: {
    trade_mode?: unknown
    copied_account_ids?: unknown
    copy_trading_group_id?: unknown
  } | null | undefined
): boolean {
  if (!trade) return false
  if (normalizeTradeMode(trade.trade_mode) === "copy_traded") return true
  if (getCopiedAccountCount(trade) > 0) return true
  const groupId = trade.copy_trading_group_id
  return groupId != null && String(groupId).trim() !== ""
}

/**
 * Badge label for trade cards.
 * Copy Traded → "Copy Traded ×N"; otherwise the account's stored status is
 * authoritative: Live / Evaluation / Funded / SIM / Backtest. The journal
 * trade_mode is only a fallback for rows without an account snapshot or
 * linked account row.
 */
export function resolveTradeModeBadgeLabel(
  trade: {
    trade_mode?: unknown
    copied_account_ids?: unknown
    copy_trading_group_id?: unknown
    account_type?: unknown
    mode?: unknown
  } | null | undefined,
  accountRow?: { mode?: unknown } | null
): string | null {
  if (!trade) return null

  if (isCopyTradedMode(trade)) {
    const n = getCopiedAccountCount(trade)
    return n > 0 ? `Copy Traded ×${n}` : "Copy Traded"
  }

  const acct = String(trade.mode ?? trade.account_type ?? accountRow?.mode ?? "")
    .trim()
    .toLowerCase()
  if (acct === "eval" || acct === "evaluation") return "Evaluation"
  if (acct === "funded") return "Funded"
  if (acct === "live") return "Live"
  if (acct === "sim") return "SIM"
  if (acct === "backtest") return "Backtest"
  if (acct === "replay") return "Replay"

  const tradeMode = normalizeTradeMode(trade.trade_mode)
  if (tradeMode) return formatTradeModeLabel(tradeMode)

  if (!acct) return null
  return (
    String(trade.mode ?? trade.account_type ?? accountRow?.mode).trim() || null
  )
}
