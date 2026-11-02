import type { DashboardSessionBucket } from "./dashboardSessionBuckets.ts"

/** Native session row order on phone: New York, London, Asia. */
export const MOBILE_WEB_SESSION_ORDER = [
  "NY",
  "London",
  "Asia",
] as const satisfies readonly DashboardSessionBucket[]

export function mobileWebSessionTitle(name: DashboardSessionBucket): string {
  return name === "NY" ? "New York" : name
}

export function mobileWebSessionWinRate(stats: {
  totalTrades: number
  wins: number
}): number {
  if (!stats.totalTrades) return 0
  return (stats.wins / stats.totalTrades) * 100
}

export function mobileWebBarShare(value: number, maxAbs: number): number {
  const ceiling = Math.max(Math.abs(maxAbs), 1)
  if (value === 0) return 0
  return Math.max(0.08, Math.min(1, Math.abs(value) / ceiling))
}

export function mobileWebWeekdayCellOpacity(value: number, maxAbs: number): number {
  if (Math.abs(value) < 0.01) return 0
  const intensity = Math.min(Math.abs(value) / Math.max(Math.abs(maxAbs), 1), 1)
  return 0.25 + intensity * 0.65
}

export function uniqueInsightCopy(lines: readonly string[]): string[] {
  const seen = new Set<string>()
  const out: string[] = []
  for (const line of lines) {
    const key = line.replace(/\s+/g, " ").trim().toLowerCase()
    if (!key || seen.has(key)) continue
    seen.add(key)
    out.push(line)
  }
  return out
}

export function insightCopyAlreadyCovers(
  lines: readonly string[],
  token: string | null | undefined
): boolean {
  if (!token) return false
  const needle = token.trim().toLowerCase()
  if (!needle) return false
  return lines.some((line) => line.toLowerCase().includes(needle))
}

export function mobileWebHourClockLabel(hour: number): string {
  const suffix = hour >= 12 ? "PM" : "AM"
  const hour12 = hour % 12 || 12
  return `${hour12} ${suffix}`
}

export function mobileWebHourAxisLabel(hour: number): string {
  const suffix = hour >= 12 ? "p" : "a"
  const hour12 = hour % 12 || 12
  return `${hour12}${suffix}`
}

export function insightRowKind(
  text: string
): "session" | "symbol" | "direction" | "combined" | "warning" | "general" {
  const lower = text.toLowerCase()
  if (/session/.test(lower)) return "session"
  if (/symbol|market|ticker/.test(lower)) return "symbol"
  if (/going long|going short|direction/.test(lower)) return "direction"
  if (/trading .+ \(/i.test(text) && /win rate/.test(lower)) return "combined"
  if (/streak|after a loss|behavior/.test(lower)) return "warning"
  return "general"
}

export function insightRowTitle(
  kind: ReturnType<typeof insightRowKind>
): string {
  switch (kind) {
    case "session":
      return "Session"
    case "symbol":
      return "Symbol"
    case "direction":
      return "Direction"
    case "combined":
      return "Combined setup"
    case "warning":
      return "Behavior"
    default:
      return "Insight"
  }
}
