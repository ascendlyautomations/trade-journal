import type { LeaderboardChartRow } from "./leaderboardChart.ts"
import { formatPnlCurrency } from "./formatMoney.ts"

export type LeaderboardChartPlotRow = LeaderboardChartRow & {
  averagePlot: number | null
  bestPlot: number | null
  worstPlot: number | null
  /** Carried-forward You series for the chart line; tooltip uses raw `you`. */
  youPlot: number | null
}

function rawPlotValues(row: LeaderboardChartRow): {
  averagePlot: number | null
  bestPlot: number | null
  worstPlot: number | null
  youPlot: number | null
} {
  if (row.contributorCount <= 1) {
    return {
      averagePlot: null,
      bestPlot: row.best,
      worstPlot: null,
      youPlot: row.you,
    }
  }
  return {
    averagePlot: row.average,
    bestPlot: row.best === row.average ? null : row.best,
    worstPlot: row.worst === row.average ? null : row.worst,
    youPlot: row.you,
  }
}

/** Hold last valid observation; no values before the first valid point. */
function carryForwardPlotSeries(values: readonly (number | null)[]): (number | null)[] {
  let last: number | null = null
  return values.map((value) => {
    if (value !== null && Number.isFinite(value)) {
      last = value
      return value
    }
    if (last === null) return null
    return last
  })
}

/**
 * Plot series for the community chart.
 * - 1 contributor: Best (green) only — no Average/Worst segment for that day.
 * - 2+ contributors: Average, Best, Worst; skip Best/Worst points when equal to Average.
 * - Each plotted series carries forward its last valid value across later buckets (flat segment).
 */
export function leaderboardChartPlotRows(
  rows: LeaderboardChartRow[]
): LeaderboardChartPlotRow[] {
  const raw = rows.map((row) => ({
    ...row,
    ...rawPlotValues(row),
  }))

  const averagePlot = carryForwardPlotSeries(raw.map((row) => row.averagePlot))
  const bestPlot = carryForwardPlotSeries(raw.map((row) => row.bestPlot))
  const worstPlot = carryForwardPlotSeries(raw.map((row) => row.worstPlot))
  const youPlot = carryForwardPlotSeries(raw.map((row) => row.youPlot))

  return raw.map((row, index) => ({
    ...row,
    averagePlot: averagePlot[index] ?? null,
    bestPlot: bestPlot[index] ?? null,
    worstPlot: worstPlot[index] ?? null,
    youPlot: youPlot[index] ?? null,
  }))
}

export type LeaderboardChartTooltipMetricKey =
  | "average"
  | "best"
  | "worst"
  | "you"

export function formatLeaderboardChartTooltipMetric(
  dataKey: LeaderboardChartTooltipMetricKey,
  value: number | null | undefined,
  contributorCount: number
): string {
  if (dataKey === "you") {
    if (value === null || value === undefined) return "—"
    return formatPnlCurrency(value, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  }

  if (contributorCount === 0) return "N/A"

  if (contributorCount === 1) {
    if (dataKey === "average" || dataKey === "worst") return "—"
    if (value === null || value === undefined) return "N/A"
    return formatPnlCurrency(value, {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    })
  }

  if (value === null || value === undefined) return "N/A"

  return formatPnlCurrency(value, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}
