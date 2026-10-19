import type { LeaderboardChartRow } from "./leaderboardChart.ts"
import { formatPnlCurrency } from "./formatMoney.ts"

export type LeaderboardChartPlotRow = LeaderboardChartRow & {
  averagePlot: number | null
  bestPlot: number | null
  worstPlot: number | null
}

/**
 * Plot series for the community chart.
 * - 1 contributor: Best (green) only — no Average/Worst segment for that day.
 * - 2+ contributors: Average, Best, Worst; skip Best/Worst points when equal to Average.
 */
export function leaderboardChartPlotRows(
  rows: LeaderboardChartRow[]
): LeaderboardChartPlotRow[] {
  return rows.map((row) => {
    if (row.contributorCount <= 1) {
      return {
        ...row,
        averagePlot: null,
        bestPlot: row.best,
        worstPlot: null,
      }
    }
    return {
      ...row,
      averagePlot: row.average,
      bestPlot: row.best === row.average ? null : row.best,
      worstPlot: row.worst === row.average ? null : row.worst,
    }
  })
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
