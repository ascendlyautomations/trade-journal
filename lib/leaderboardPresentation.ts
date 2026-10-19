import {
  formatProfitFactor,
  formatRR,
  formatSignedPnlDisplay,
} from "./formatDisplay.ts"
import { formatPnlCurrency } from "./formatMoney.ts"
import type {
  LeaderboardBootstrapCategory,
  LeaderboardBootstrapRow,
} from "./leaderboardBootstrap.ts"
import type { LeaderboardRankedTrader } from "./leaderboardChart.ts"

export function leaderboardCategoryLabel(
  category: LeaderboardBootstrapCategory
): string {
  switch (category) {
    case "pnl":
      return "PnL"
    case "win_rate":
      return "Win Rate"
    case "profit_factor":
      return "Profit Factor"
    case "expectancy":
      return "Expectancy"
    case "rr":
      return "RR"
    case "winstreak":
      return "Win Streak"
    case "profitpercent":
      return "Profit %"
    case "followers":
      return "Followers"
    case "consistency":
      return "Consistency"
  }
}

function formatWinRateFraction(rate: number | null | undefined): string {
  if (rate === null || rate === undefined || !Number.isFinite(rate)) return "—"
  return `${(rate * 100).toLocaleString(undefined, {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })}%`
}

function formatPercentScale(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—"
  return `${value.toLocaleString(undefined, {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })}%`
}

function formatExpectancy(value: number | null | undefined): string {
  if (value === null || value === undefined || !Number.isFinite(value)) return "—"
  return formatPnlCurrency(value, {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })
}

function formatFollowerCount(count: number): string {
  return count.toLocaleString()
}

function tradeDetailLine(row: LeaderboardBootstrapRow): string {
  if (row.avgRr != null && Number.isFinite(row.avgRr)) {
    return `${row.tradeCount.toLocaleString()} · ${formatRR(row.avgRr)} RR`
  }
  return row.tradeCount.toLocaleString()
}

export function leaderboardPrimaryMetricText(
  row: LeaderboardBootstrapRow,
  category: LeaderboardBootstrapCategory
): string {
  switch (category) {
    case "pnl":
      return formatSignedPnlDisplay(row.totalPnl)
    case "win_rate":
      return formatWinRateFraction(row.winRate)
    case "profit_factor":
      return formatProfitFactor(row.profitFactor)
    case "expectancy":
      return formatExpectancy(row.expectancy)
    case "rr":
      return formatRR(row.avgRr)
    case "winstreak":
      return row.winStreak.toLocaleString()
    case "profitpercent":
      return formatPercentScale(row.profitPercent)
    case "consistency":
      return formatPercentScale(row.consistency)
    case "followers":
      return formatFollowerCount(row.followerCount)
  }
}

export function leaderboardSecondaryMetricText(
  row: LeaderboardBootstrapRow,
  category: LeaderboardBootstrapCategory
): string {
  switch (category) {
    case "followers":
      return formatSignedPnlDisplay(row.totalPnl)
    case "pnl":
      return tradeDetailLine(row)
    case "win_rate":
    case "profit_factor":
    case "expectancy":
    case "profitpercent":
    case "consistency":
      return formatSignedPnlDisplay(row.totalPnl)
    case "rr":
    case "winstreak":
      return row.tradeCount.toLocaleString()
  }
}

export function leaderboardLegacyPrimaryMetricText(
  row: LeaderboardRankedTrader
): string {
  return formatSignedPnlDisplay(row.totalPnl)
}

export function leaderboardLegacySecondaryMetricText(
  row: LeaderboardRankedTrader
): string {
  if (row.avgRR != null && Number.isFinite(row.avgRR)) {
    return `${row.tradeCount.toLocaleString()} · ${formatRR(row.avgRR)} RR`
  }
  return row.tradeCount.toLocaleString()
}

export type LeaderboardTableRow = {
  rank: number
  userId: string
  primaryMetric: string
  secondaryMetric: string
  pnlForColor: number | null
}

export function leaderboardTableRowsFromBootstrap(
  rows: LeaderboardBootstrapRow[],
  category: LeaderboardBootstrapCategory,
  rankOffset = 0
): LeaderboardTableRow[] {
  return rows.map((row, index) => ({
    rank: rankOffset + index + 1,
    userId: row.profileId,
    primaryMetric: leaderboardPrimaryMetricText(row, category),
    secondaryMetric: leaderboardSecondaryMetricText(row, category),
    pnlForColor: category === "pnl" ? row.totalPnl : row.totalPnl,
  }))
}

export function leaderboardTableRowsFromLegacy(
  rows: LeaderboardRankedTrader[]
): LeaderboardTableRow[] {
  return rows.map((row) => ({
    rank: row.rank,
    userId: row.userId,
    primaryMetric: leaderboardLegacyPrimaryMetricText(row),
    secondaryMetric: leaderboardLegacySecondaryMetricText(row),
    pnlForColor: row.totalPnl,
  }))
}
