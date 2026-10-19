import { stressAverageDisplayText } from "../display.ts"

export function formatPsychologyInteger(value: number): string {
  return Math.round(value).toLocaleString("en-US")
}

export function formatPsychologyDecimal(
  value: number,
  minimumFractionDigits: number,
  maximumFractionDigits: number
): string {
  if (!Number.isFinite(value)) return "—"
  return value.toLocaleString("en-US", {
    minimumFractionDigits,
    maximumFractionDigits,
  })
}

export function formatPsychologyMoney(value: number): string {
  if (!Number.isFinite(value)) return "—"
  const rounded = Math.round(value)
  const formatted = Math.abs(rounded).toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  })
  return rounded < 0 ? `-$${formatted}` : `$${formatted}`
}

export function formatPsychologyPercent(value: number): string {
  if (!Number.isFinite(value)) return "—"
  return `${Math.round(value)}%`
}

export function formatPsychologyWinRate(rate: number | null): string {
  if (rate == null || !Number.isFinite(rate)) return "—"
  return formatPsychologyPercent(rate * 100)
}

export function formatPsychologyRatio(value: number | null): string {
  if (value == null || !Number.isFinite(value)) return "—"
  return formatPsychologyDecimal(value, 0, 2)
}

export function formatPsychologyHours(value: number): string {
  return `${formatPsychologyDecimal(value, 1, 1)}h`
}

export function formatPsychologyRating(value: number): string {
  return `${formatPsychologyDecimal(value, 1, 1)}/5`
}

export function formatPsychologyStressAverage(value: number): string {
  return stressAverageDisplayText(value)
}
