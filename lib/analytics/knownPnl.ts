/** Finite P&L, or null when the result was not recorded. Never treats null as $0. */
export function knownPnl(value: unknown): number | null {
  if (value == null || value === "") return null
  if (typeof value === "string" && value.trim() === "") return null
  const n = typeof value === "number" ? value : Number(value)
  return Number.isFinite(n) ? n : null
}

/** Each side of a comparative performance claim needs this many priced trades. */
export const COMPARATIVE_MIN_PER_SIDE = 5

export function easternHour(instant: Date): number | null {
  if (Number.isNaN(instant.getTime())) return null
  const hour = Number(
    new Intl.DateTimeFormat("en-US", {
      timeZone: "America/New_York",
      hour: "numeric",
      hourCycle: "h23",
    })
      .formatToParts(instant)
      .find((part) => part.type === "hour")?.value
  )
  if (!Number.isFinite(hour)) return null
  return hour === 24 ? 0 : hour
}

type RankedGroup = {
  avgPnL: number
  trades: number
}

/** Leading group only when another group is also large enough, and the lead is not flat. */
export function qualifiedExtreme<T extends RankedGroup>(
  groups: readonly T[],
  mode: "best" | "worst"
): T | null {
  const ranked = groups.filter((group) => group.trades >= COMPARATIVE_MIN_PER_SIDE)
  if (ranked.length < 2) return null
  const sorted = [...ranked].sort((a, b) =>
    mode === "best" ? b.avgPnL - a.avgPnL : a.avgPnL - b.avgPnL
  )
  const lead = sorted[0]
  const next = sorted[1]
  if (lead.avgPnL === next.avgPnL) return null
  if (mode === "best" && lead.avgPnL <= 0) return null
  if (mode === "worst" && lead.avgPnL >= 0) return null
  return lead
}
