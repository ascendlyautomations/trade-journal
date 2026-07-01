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

/** Strip grouping/currency symbols from a trade input string. */
export function cleanTradeNumericInput(value: string): string {
  return value.replace(/,/g, "").replace(/\$/g, "")
}

export function parseTradeNumericInput(value: string): number | null {
  const cleaned = cleanTradeNumericInput(value)
  if (cleaned === "" || cleaned === "-" || cleaned === "-.") return null
  const num = Number(cleaned)
  return Number.isFinite(num) ? num : null
}

/** Intermediate typing states that should not be reformatted in currency inputs. */
export function isIntermediateNumericInput(value: string): boolean {
  return (
    value === "" ||
    value === "-" ||
    value === "." ||
    value === "-." ||
    value.endsWith(".")
  )
}

/** Display formatter for P&L inputs (always two decimal places). */
export function formatTradeInputPnlDisplay(value: string): string {
  if (!value) return ""
  if (isIntermediateNumericInput(value)) return value
  const num = parseTradeNumericInput(value)
  if (num === null) return ""
  return formatPnlCurrency(num)
}

/** Display formatter for price inputs (preserves imported decimal precision). */
export function formatTradeInputPriceDisplay(value: string): string {
  if (!value) return ""
  if (isIntermediateNumericInput(value)) return value
  const num = parseTradeNumericInput(value)
  if (num === null) return ""
  const cleaned = cleanTradeNumericInput(value)
  const dot = cleaned.indexOf(".")
  const fractionDigits =
    dot === -1 ? 2 : Math.max(2, cleaned.length - dot - 1)
  return formatPnlCurrency(num, {
    minimumFractionDigits: 2,
    maximumFractionDigits: fractionDigits,
  })
}

export function handleTradeNumericInput(
  value: string,
  setter: (val: string) => void,
  options?: {
    allowDecimal?: boolean
    allowNegative?: boolean
  }
): void {
  let cleaned = cleanTradeNumericInput(value)
  const { allowDecimal = false, allowNegative = false } = options ?? {}

  if (allowDecimal) {
    const decimalCount = (cleaned.match(/\./g) ?? []).length
    if (decimalCount > 1) return
  }

  let regex: RegExp
  if (allowDecimal && allowNegative) {
    regex = /^-?\d*(\.\d*)?$/
  } else if (allowDecimal) {
    regex = /^\d*(\.\d*)?$/
  } else if (allowNegative) {
    regex = /^-?\d*$/
  } else {
    regex = /^\d*$/
  }

  if (isIntermediateNumericInput(cleaned)) {
    setter(cleaned)
    return
  }

  if (!regex.test(cleaned)) return
  setter(cleaned)
}
