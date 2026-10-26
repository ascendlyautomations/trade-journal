import { createHash } from "node:crypto"

/** Stable CSV row identity for idempotent re-import (per user + account). */
export function csvTradeImportFingerprint(trade: {
  account_id?: string | null
  ticker?: string | null
  direction?: string | null
  entry_time?: string | null
  exit_time?: string | null
  trade_date?: string | null
  date?: string | null
  pnl?: number | null
  contracts?: number | null
  entry_price?: number | null
  exit_price?: number | null
}): string {
  const norm = (v: unknown) => String(v ?? "").trim().toLowerCase()
  const normNum = (v: unknown) => {
    const n = Number(v)
    return Number.isFinite(n) ? n.toFixed(4) : ""
  }
  const payload = [
    norm(trade.account_id),
    norm(trade.ticker),
    norm(trade.direction),
    norm(trade.entry_time),
    norm(trade.exit_time),
    norm(trade.trade_date || trade.date),
    normNum(trade.pnl),
    normNum(trade.contracts),
    normNum(trade.entry_price),
    normNum(trade.exit_price),
  ].join("|")
  const digest = createHash("sha256").update(payload, "utf8").digest("hex")
  return `v1:${digest}`
}
