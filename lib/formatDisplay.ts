import { formatPnlCurrency, type PnlFormatOptions } from "./formatMoney"

export type FormatUnknownOptions = PnlFormatOptions & {
  /** Shown when value is null/undefined/NaN (TradeCard uses "-", share cards use "—"). */
  empty?: string
}

/**
 * P&L-style currency for unknown trade fields (matches TradeCard / trades list).
 */
export function formatMoneyUnknown(
  value: unknown,
  opts: FormatUnknownOptions = {}
): string {
  const empty = opts.empty ?? "-"
  if (value === null || value === undefined) return empty
  const number = Number(value)
  if (Number.isNaN(number)) return empty
  return formatPnlCurrency(number, opts)
}

/** Non-currency numeric display (RR, size, etc.). */
export function formatNumberUnknown(value: unknown, empty = "-"): string {
  if (value === null || value === undefined) return empty
  const number = Number(value)
  if (Number.isNaN(number)) return empty
  return number.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

export function formatDecimal(value: number, maxFractionDigits = 2): string {
  if (!Number.isFinite(value)) return "—"
  return value.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: maxFractionDigits,
  })
}

export function formatRR(value: unknown, empty = "—"): string {
  return formatNumberUnknown(value, empty)
}

export function formatPoints(value: unknown, empty = "—"): string {
  return formatNumberUnknown(value, empty)
}

export function formatSignedPnlDisplay(value: unknown, empty = "—"): string {
  if (value === null || value === undefined) return empty
  const number = Number(value)
  if (!Number.isFinite(number)) return empty
  const formatted = formatPnlCurrency(number, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
  return number > 0 ? `+${formatted}` : formatted
}

/**
 * Human-readable duration from entry/exit timestamps (TradeCard / trades page).
 */
export function getDurationFromTimes(
  start: string | null | undefined,
  end: string | null | undefined
): string | null {
  if (!start || !end) return null

  const diff = +new Date(String(end)) - +new Date(String(start))
  if (!Number.isFinite(diff) || diff <= 0) return null

  const totalSeconds = Math.floor(diff / 1000)
  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60

  if (hours === 0 && minutes === 0) {
    return "0m"
  }

  if (hours === 0) {
    return seconds > 0 ? `${minutes}m ${seconds}s` : `${minutes}m`
  }

  return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`
}

export function pnlIsPositive(value: unknown): boolean | null {
  if (value === null || value === undefined) return null
  const n = Number(value)
  if (!Number.isFinite(n)) return null
  return n >= 0
}

export type PnlTextColorVariant = "emerald" | "green"

/**
 * Tailwind text class for signed P&L (matches feed/explore/calendar conventions).
 */
export function pnlTextClassName(
  value: unknown,
  opts?: {
    variant?: PnlTextColorVariant
    zeroClass?: string
    invalidClass?: string
  }
): string {
  const sign = pnlIsPositive(value)
  if (sign === null) {
    return opts?.invalidClass ?? opts?.zeroClass ?? "text-gray-300"
  }
  if (sign) {
    return opts?.variant === "green" ? "text-green-400" : "text-emerald-400"
  }
  return "text-red-400"
}
