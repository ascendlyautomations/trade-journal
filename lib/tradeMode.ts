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
 * Copy Traded → "Copy Traded ×N"; other modes → Live / SIM / Replay / Backtest.
 * Falls back to legacy account_type/mode when trade_mode is unset.
 */
export function resolveTradeModeBadgeLabel(
  trade: {
    trade_mode?: unknown
    copied_account_ids?: unknown
    copy_trading_group_id?: unknown
    account_type?: unknown
    mode?: unknown
  } | null | undefined
): string | null {
  if (!trade) return null

  if (isCopyTradedMode(trade)) {
    const n = getCopiedAccountCount(trade)
    return n > 0 ? `Copy Traded ×${n}` : "Copy Traded"
  }

  const tradeMode = normalizeTradeMode(trade.trade_mode)
  if (tradeMode) return formatTradeModeLabel(tradeMode)

  const legacy = String(trade.account_type ?? trade.mode ?? "")
    .trim()
    .toLowerCase()
  if (!legacy) return null
  if (legacy === "sim") return "SIM"
  if (legacy === "live") return "Live"
  if (legacy === "backtest") return "Backtest"
  if (legacy === "replay") return "Replay"
  if (legacy === "eval") return "Eval"
  if (legacy === "funded") return "Funded"
  return String(trade.account_type ?? trade.mode).trim() || null
}
