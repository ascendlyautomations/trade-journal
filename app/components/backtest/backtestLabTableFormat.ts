import { formatPnlCurrency } from "@/lib/formatMoney"
import { formatRR } from "@/lib/formatDisplay"
import type { BacktestLabGroupStats } from "@/lib/backtestLabAnalytics"

export function formatBacktestLabWinRate(value: number | null): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return `${value.toFixed(1)}%`
}

export function formatBacktestLabProfitFactor(row: {
  profitFactor: number | null
  profitFactorInfinite: boolean
}): string {
  if (row.profitFactorInfinite) return "∞"
  if (row.profitFactor == null || !Number.isFinite(row.profitFactor)) return "—"
  return row.profitFactor.toFixed(2)
}

export function formatBacktestLabExpectancy(value: number | null): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return formatPnlCurrency(value, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

export function formatBacktestLabAvgWinLoss(value: number | null): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return formatPnlCurrency(value, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

export function formatBacktestLabNetPnl(value: number): string {
  return formatPnlCurrency(value, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

export function formatBacktestLabAvgR(value: number | null): string {
  return formatRR(value)
}

export function pnlToneClass(value: number): string {
  if (value > 0) return "text-emerald-400"
  if (value < 0) return "text-red-400"
  return "text-gray-200"
}

export type BacktestLabTableColumn = {
  id: string
  label: string
  align?: "left" | "right"
  cell: (row: BacktestLabGroupStats) => string
  cellClass?: (row: BacktestLabGroupStats) => string | undefined
}
