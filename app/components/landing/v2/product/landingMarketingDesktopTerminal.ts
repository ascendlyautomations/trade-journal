import type { DashboardDesktopTerminalProps } from "@/app/components/dashboard/DashboardDesktopTerminal"
import { getMarketingDashboardData } from "@/app/components/marketing-ads/marketingDemoData"
import { computeMaxDrawdown } from "@/lib/dashboardMaxDrawdown"
import { computeHoldTimeStats } from "@/lib/dashboardHoldTimeStats"
import { computeLongShortPerformance } from "@/lib/dashboardLongShortStats"
import { getDashboardTradingDayKey } from "@/lib/dashboardTradeDate"
import { computeDemoDashboardStats } from "@/lib/demo/computeDemoDashboard"
import { DEMO_TRADES } from "@/lib/demo/fixtures"
import { averageMaxRrReachedFromTrades } from "@/lib/tradeRr"

function tradingHoursFromHourlyMap(hourlyMap: Record<number, number>) {
  let hasValidTradingHoursData = false
  let bestHour: number | null = null
  let worstHour: number | null = null
  let bestPnl = -Infinity
  let worstPnl = Infinity

  for (const [hourKey, pnl] of Object.entries(hourlyMap)) {
    hasValidTradingHoursData = true
    const hour = Number(hourKey)
    if (pnl > bestPnl) {
      bestPnl = pnl
      bestHour = hour
    }
    if (pnl < worstPnl) {
      worstPnl = pnl
      worstHour = hour
    }
  }

  return {
    hourlyMap,
    hasValidTradingHoursData,
    bestHour,
    worstHour,
  }
}

/** Demo props for {@link DashboardDesktopTerminal} on the marketing homepage. */
export function getLandingMarketingDesktopTerminalProps(): DashboardDesktopTerminalProps {
  const trades = DEMO_TRADES
  const stats = computeDemoDashboardStats(trades)
  const { sessionBuckets, weekdayChart } = getMarketingDashboardData()

  const winCount = trades.filter((t) => Number(t.pnl) > 0).length
  const lossCount = trades.filter((t) => Number(t.pnl) < 0).length

  const dailyKeys = new Set<string>()
  for (const trade of trades) {
    const key = getDashboardTradingDayKey(trade)
    if (key) dailyKeys.add(key)
  }

  return {
    isPro: true,
    deferredSectionsReady: true,
    timeframeLabel: "Last 30 Days",
    propFirmDetails: null,
    totalTrades: stats.totalTrades,
    totalPnL: stats.totalPnL,
    winRate: stats.winRate,
    winCount,
    lossCount,
    profitFactor: stats.profitFactor,
    avgRR: stats.avgRR,
    avgMaxRrReached: averageMaxRrReachedFromTrades(trades),
    expectancyData: { expectancy: stats.expectancy },
    bestDay: stats.bestDay,
    bestTrade: stats.bestTrade,
    avgWin: stats.avgWin,
    avgLoss: stats.avgLoss,
    biggestLoss: stats.biggestLoss,
    worstDay: stats.worstDay,
    periodTradingDayCount: dailyKeys.size,
    maxDrawdown: computeMaxDrawdown(trades),
    showDrawdown: true,
    bestWinStreak: stats.maxWinStreak,
    streakData: {
      currentStreak: stats.currentStreak,
      currentType: stats.currentStreakType,
    },
    showEquity: true,
    equityData: stats.equityCurve,
    showSessions: true,
    sessionBuckets,
    weekdayData: weekdayChart,
    hourData: tradingHoursFromHourlyMap(stats.hourlyMap),
    longShortPerformance: computeLongShortPerformance(trades),
    holdTimeStats: computeHoldTimeStats(trades),
    liveAccountValue: null,
    drawdownLimitLineY: null,
    equityCurveUsesAccountBalance: false,
    showPersonalDrawdownFloor: false,
  }
}
