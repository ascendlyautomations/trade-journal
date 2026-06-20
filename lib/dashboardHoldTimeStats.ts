export type TradeDurationFields = {
  duration_seconds?: unknown
  entry_time?: string | null
  exit_time?: string | null
  pnl?: unknown
}

export type DurationExtreme = {
  durationSeconds: number
  pnl: number
}

export type HoldTimeStats = {
  tradesWithDuration: number
  avgHoldSeconds: number | null
  winningAvgHoldSeconds: number | null
  losingAvgHoldSeconds: number | null
  fastestWinner: DurationExtreme | null
  longestWinner: DurationExtreme | null
  fastestLoser: DurationExtreme | null
  longestLoser: DurationExtreme | null
  hasDurationData: boolean
}

/** Seconds held; prefers duration_seconds, then exit_time − entry_time. */
export function resolveTradeDurationSeconds(
  trade: Pick<TradeDurationFields, "duration_seconds" | "entry_time" | "exit_time">
): number | null {
  const seconds = trade.duration_seconds
  if (seconds !== null && seconds !== undefined && seconds !== "") {
    const n = Math.floor(Number(seconds))
    if (Number.isFinite(n) && n > 0) return n
  }

  const entry = trade.entry_time
  const exit = trade.exit_time
  if (!entry || !exit) return null

  const diff = +new Date(String(exit)) - +new Date(String(entry))
  if (!Number.isFinite(diff) || diff <= 0) return null
  return Math.floor(diff / 1000)
}

function averageSeconds(values: number[]): number | null {
  if (values.length === 0) return null
  return values.reduce((sum, value) => sum + value, 0) / values.length
}

function pickExtreme(
  items: { seconds: number; pnl: number }[],
  mode: "min" | "max"
): DurationExtreme | null {
  if (items.length === 0) return null

  let picked = items[0]
  for (let i = 1; i < items.length; i += 1) {
    const candidate = items[i]
    if (mode === "min" ? candidate.seconds < picked.seconds : candidate.seconds > picked.seconds) {
      picked = candidate
    }
  }

  return { durationSeconds: picked.seconds, pnl: picked.pnl }
}

export function computeHoldTimeStats(
  trades: TradeDurationFields[]
): HoldTimeStats {
  const withDuration: { seconds: number; pnl: number }[] = []

  for (const trade of trades) {
    const seconds = resolveTradeDurationSeconds(trade)
    if (seconds === null) continue
    withDuration.push({ seconds, pnl: Number(trade.pnl) || 0 })
  }

  const winners = withDuration.filter((t) => t.pnl > 0)
  const losers = withDuration.filter((t) => t.pnl < 0)

  return {
    tradesWithDuration: withDuration.length,
    avgHoldSeconds: averageSeconds(withDuration.map((t) => t.seconds)),
    winningAvgHoldSeconds: averageSeconds(winners.map((t) => t.seconds)),
    losingAvgHoldSeconds: averageSeconds(losers.map((t) => t.seconds)),
    fastestWinner: pickExtreme(winners, "min"),
    longestWinner: pickExtreme(winners, "max"),
    fastestLoser: pickExtreme(losers, "min"),
    longestLoser: pickExtreme(losers, "max"),
    hasDurationData: withDuration.length > 0,
  }
}
