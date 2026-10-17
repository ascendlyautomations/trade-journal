"use client"

import { useMemo } from "react"
import {
  sumPayoutAchievementTotals,
  type Achievement,
} from "@/lib/achievements"
import { averageRrFromTrades } from "@/lib/tradeRr"
import type { ProfileStatisticsMode } from "@/app/components/profile/ProfileStatisticsTab"
import type { ProfileTradeRow } from "@/app/components/profile/profileTypes"
import {
  computeProfileOverviewWinRate,
  profileTradeMatchesStatisticsMode,
  type ProfilePublicStatsAggregate,
} from "@/lib/profilePublicStatistics"
import { computeTradeOutcomeStreaks } from "@/lib/userStreaksLogic"

function profitFactorFromTrades(
  trades: Array<{ pnl?: unknown }>
): number | null {
  let grossWins = 0
  let grossLosses = 0
  for (const trade of trades) {
    const pnl = Number(trade.pnl) || 0
    if (pnl > 0) grossWins += pnl
    else if (pnl < 0) grossLosses += pnl
  }
  return grossLosses < 0 ? grossWins / Math.abs(grossLosses) : null
}

type UseProfileStatisticsOptions = {
  visibleTrades: ProfileTradeRow[]
  analyticsTradeRows: ProfileTradeRow[]
  summaryTrades: ProfileTradeRow[]
  bootstrapOverviewStats: ProfilePublicStatsAggregate | null
  selectedMode: ProfileStatisticsMode
  canViewTrades: boolean
  analyticsTradesReady: boolean
  analyticsTradesLoading: boolean
  summaryReady: boolean
  achievements: Achievement[]
  achievementsReady: boolean
  /** Chronological equity from statistics mode `all`. Used when summary trades are not loaded. */
  streakEquity?: Array<{ equity: number }> | null
}

export function useProfileStatistics({
  visibleTrades,
  analyticsTradeRows,
  summaryTrades,
  bootstrapOverviewStats,
  selectedMode,
  canViewTrades,
  analyticsTradesReady,
  analyticsTradesLoading,
  summaryReady,
  achievements,
  achievementsReady,
  streakEquity = null,
}: UseProfileStatisticsOptions) {
  return useMemo(() => {
    const sortedTrades = [...visibleTrades].sort((a, b) => {
      if (a.is_pinned && !b.is_pinned) return -1
      if (!a.is_pinned && b.is_pinned) return 1
      return (
        new Date(b.created_at ?? 0).getTime() -
        new Date(a.created_at ?? 0).getTime()
      )
    })

    const profilePublicTrades = analyticsTradeRows.filter(
      (trade) => trade.is_public === true
    )
    const filteredTrades = profilePublicTrades.filter((trade) =>
      profileTradeMatchesStatisticsMode(trade, selectedMode)
    )

    const analyticsTrades = filteredTrades.filter((trade) => {
      const modeValue = String(trade.mode ?? "").trim().toLowerCase()
      const accountType = String(trade.account_type ?? "")
        .trim()
        .toLowerCase()
      return modeValue !== "backtest" && accountType !== "backtest"
    })
    const profileOverviewTrades = summaryTrades.filter((trade) => {
      const modeValue = String(trade.mode ?? "").trim().toLowerCase()
      const accountType = String(trade.account_type ?? "")
        .trim()
        .toLowerCase()
      return modeValue !== "backtest" && accountType !== "backtest"
    })

    const useBootstrapOverview =
      bootstrapOverviewStats != null && summaryTrades.length === 0

    const statsVisible =
      canViewTrades && analyticsTradesReady && !analyticsTradesLoading
    const overviewStatsVisible =
      canViewTrades && (summaryReady || useBootstrapOverview)
    const totalTrades = canViewTrades ? analyticsTrades.length : 0
    const wins = canViewTrades
      ? analyticsTrades.filter((trade) => Number(trade.pnl) > 0).length
      : 0
    const totalPnl = canViewTrades
      ? analyticsTrades.reduce(
          (sum, trade) => sum + (Number(trade.pnl) || 0),
          0
        )
      : 0
    const biggestWin = analyticsTrades.length
      ? Math.max(...analyticsTrades.map((trade) => Number(trade.pnl) || 0))
      : 0
    const losingPnls = analyticsTrades
      .map((trade) => Number(trade.pnl) || 0)
      .filter((pnl) => pnl < 0)
    const biggestLoss =
      losingPnls.length > 0 ? Math.min(...losingPnls) : null
    const longTrades = analyticsTrades.filter(
      (trade) => trade.direction === "Long"
    ).length

    const equityData = analyticsTrades
      .slice()
      .reverse()
      .reduce(
        (acc: Array<{ index: number; equity: number }>, trade, index) => {
          const previous = acc[index - 1]?.equity || 0
          acc.push({
            index,
            equity: previous + (Number(trade.pnl) || 0),
          })
          return acc
        },
        []
      )
    const currentEquity =
      equityData.length > 0 ? equityData[equityData.length - 1].equity : 0

    const overviewTotalTrades = overviewStatsVisible
      ? useBootstrapOverview
        ? bootstrapOverviewStats.totalTrades
        : profileOverviewTrades.length
      : 0
    const overviewWins = overviewStatsVisible
      ? useBootstrapOverview
        ? bootstrapOverviewStats.wins
        : profileOverviewTrades.filter(
            (trade) => (Number(trade.pnl) || 0) > 0
          ).length
      : 0
    const overviewWinRate = overviewStatsVisible
      ? useBootstrapOverview
        ? computeProfileOverviewWinRate(bootstrapOverviewStats)
        : overviewTotalTrades
          ? (overviewWins / overviewTotalTrades) * 100
          : 0
      : 0
    const overviewTotalPnL = overviewStatsVisible
      ? useBootstrapOverview
        ? bootstrapOverviewStats.totalPnl
        : profileOverviewTrades.reduce(
            (sum, trade) => sum + (Number(trade.pnl) || 0),
            0
          )
      : 0
    const overviewAvgRR = overviewStatsVisible
      ? useBootstrapOverview
        ? bootstrapOverviewStats.avgRr
        : averageRrFromTrades(profileOverviewTrades)
      : null
    const achievementPayout = achievementsReady
      ? sumPayoutAchievementTotals(achievements)
      : null
    // Summary trades do not include payouts. Keep the bootstrap total once it
    // arrives, including 0, so an achievements-tab sum cannot replace it.
    const overviewPayoutTotal =
      bootstrapOverviewStats?.payoutTotal != null
        ? bootstrapOverviewStats.payoutTotal
        : achievementPayout
    const overviewProfitFactor = overviewStatsVisible
      ? useBootstrapOverview
        ? bootstrapOverviewStats.profitFactor
        : profitFactorFromTrades(profileOverviewTrades)
      : null
    const currentStreakLabel = (() => {
      if (!overviewStatsVisible) return "—"
      if (!useBootstrapOverview && profileOverviewTrades.length > 0) {
        return formatOutcomeStreakLabel(profileOverviewTrades)
      }
      if (streakEquity && streakEquity.length > 0) {
        return formatOutcomeStreakLabel(tradesFromEquity(streakEquity))
      }
      return "—"
    })()

    const grossWins = analyticsTrades.reduce((sum, trade) => {
      const pnl = Number(trade.pnl) || 0
      return pnl > 0 ? sum + pnl : sum
    }, 0)
    const grossLosses = analyticsTrades.reduce((sum, trade) => {
      const pnl = Number(trade.pnl) || 0
      return pnl < 0 ? sum + pnl : sum
    }, 0)
    const profitFactor =
      statsVisible && grossLosses < 0
        ? grossWins / Math.abs(grossLosses)
        : null
    const avgWinner = wins > 0 ? grossWins / wins : null
    const lossCount = canViewTrades
      ? analyticsTrades.filter(
          (trade) => (Number(trade.pnl) || 0) < 0
        ).length
      : 0
    const avgLoser = lossCount > 0 ? grossLosses / lossCount : null
    const profitPerTrade = totalTrades > 0 ? totalPnl / totalTrades : null

    const { maxWinStreak, maxLossStreak } = (() => {
      const streaks = computeTradeOutcomeStreaks(analyticsTrades)
      return {
        maxWinStreak: streaks.longestWin,
        maxLossStreak: streaks.longestLoss,
      }
    })()

    const sessionCounts = analyticsTrades.reduce<Record<string, number>>(
      (counts, trade) => {
        const raw = String(trade.session ?? "").toLowerCase().trim()
        let label: "NY" | "London" | "Asia" | null = null
        if (raw.includes("ny") || raw.includes("new york")) label = "NY"
        else if (
          raw.includes("london") ||
          raw.includes("ldn") ||
          raw.includes("uk")
        ) {
          label = "London"
        } else if (
          raw.includes("asia") ||
          raw.includes("asian") ||
          raw.includes("tokyo")
        ) {
          label = "Asia"
        }
        if (label) counts[label] = (counts[label] || 0) + 1
        return counts
      },
      {}
    )
    const sessionTotal = Object.values(sessionCounts).reduce(
      (sum, count) => sum + count,
      0
    )
    const sessionBreakdown = (["NY", "London", "Asia"] as const)
      .map((label) => {
        const count = sessionCounts[label] || 0
        const pct = sessionTotal > 0 ? (count / sessionTotal) * 100 : 0
        return { label, count, pct }
      })
      .filter((row) => row.count > 0)

    return {
      sortedTrades,
      filteredTrades,
      statsVisible,
      overviewStatsVisible,
      biggestWin,
      biggestLoss,
      longTrades,
      equityData,
      currentEquity,
      overviewTotalTrades,
      overviewWinRate,
      overviewTotalPnL,
      overviewAvgRR,
      overviewPayoutTotal,
      overviewProfitFactor,
      currentStreakLabel,
      profitFactor,
      avgWinner,
      avgLoser,
      profitPerTrade,
      maxWinStreak,
      maxLossStreak,
      sessionTotal,
      sessionBreakdown,
    }
  }, [
    achievements,
    achievementsReady,
    analyticsTradeRows,
    analyticsTradesLoading,
    analyticsTradesReady,
    bootstrapOverviewStats,
    canViewTrades,
    selectedMode,
    summaryReady,
    streakEquity,
    summaryTrades,
    visibleTrades,
  ])
}

function formatOutcomeStreakLabel(
  trades: Array<{ pnl?: unknown; created_at?: string | null }>
): string {
  const streaks = computeTradeOutcomeStreaks(trades)
  if (streaks.currentWin > 0) return `W${streaks.currentWin}`
  if (streaks.currentLoss > 0) return `L${streaks.currentLoss}`
  return "—"
}

/** Equity points are already chronological. Index timestamps keep that order. */
function tradesFromEquity(points: Array<{ equity: number }>) {
  let previous = 0
  return points.map((point, index) => {
    const pnl = point.equity - previous
    previous = point.equity
    return { pnl, created_at: new Date(index).toISOString() }
  })
}
