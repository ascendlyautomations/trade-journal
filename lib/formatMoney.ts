/**
 * Shared P&L / currency formatting (aligned with TradeCard + trades page).
 * Negative values render as -$X (minus before the dollar sign).
 */

export type PnlFormatOptions = {
  minimumFractionDigits?: number
  maximumFractionDigits?: number
}

export function formatPnlCurrency(
  value: number,
  opts: PnlFormatOptions = {}
): string {
  const min = opts.minimumFractionDigits ?? 2
  const max = opts.maximumFractionDigits ?? 2
  if (!Number.isFinite(value)) return "—"
  const abs = Math.abs(value)
  const formatted = abs.toLocaleString(undefined, {
    minimumFractionDigits: min,
    maximumFractionDigits: max,
  })
  return value < 0 ? `-$${formatted}` : `$${formatted}`
}
