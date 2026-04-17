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

/**
 * Whole-dollar P&L for compact calendar cells (no cents, en-US grouping).
 * Negative: -$55. Zero: $0.
 */
export function formatPnlWholeDollars(value: number): string {
  if (!Number.isFinite(value)) return "—"
  const rounded = Math.round(value)
  const abs = Math.abs(rounded)
  const formatted = abs.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })
  return rounded < 0 ? `-$${formatted}` : `$${formatted}`
}
