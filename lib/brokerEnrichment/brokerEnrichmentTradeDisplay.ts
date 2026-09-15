import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatShortDateTimeEST } from "@/lib/formatDate"
import type { BrokerEnrichmentTradeRow } from "@/lib/brokerEnrichment/brokerEnrichmentTypes"

function formatClock(iso: string | null): string {
  if (!iso) return "—"
  const formatted = formatShortDateTimeEST(iso)
  if (!formatted) return "—"
  const parts = formatted.split(", ")
  return parts.length > 1 ? parts[parts.length - 1]! : formatted
}

export function brokerEnrichmentTradeHeadline(trade: BrokerEnrichmentTradeRow): string {
  const ticker = trade.ticker?.trim() || "—"
  const direction = trade.direction?.trim() || "—"
  return `${ticker} · ${direction}`
}

export function brokerEnrichmentPnlLine(trade: BrokerEnrichmentTradeRow): string {
  if (trade.pnl === null || trade.pnl === undefined || trade.pnl === "") return "—"
  const n = Number(trade.pnl)
  return Number.isFinite(n) ? formatPnlCurrency(n) : String(trade.pnl)
}

export function brokerEnrichmentContractsLine(trade: BrokerEnrichmentTradeRow): string {
  const n = trade.contracts
  if (n == null || !Number.isFinite(Number(n))) return "—"
  const c = Number(n)
  return `${c} contract${c === 1 ? "" : "s"}`
}

export function brokerEnrichmentTimeRangeLine(trade: BrokerEnrichmentTradeRow): string {
  const entry = formatClock(trade.entry_time)
  const exit = formatClock(trade.exit_time)
  if (entry === "—" && exit === "—") return "—"
  return `${entry} → ${exit}`
}

export function brokerEnrichmentAccountLine(trade: BrokerEnrichmentTradeRow): string {
  return trade.account_name?.trim() || "Trading account"
}
