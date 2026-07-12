import { computeDemoDashboardStats } from "@/lib/demo/computeDemoDashboard"
import { DEMO_TRADES } from "@/lib/demo/fixtures"
import {
  DASHBOARD_SESSION_DISPLAY_ORDER,
  normalizeSessionBucket,
  type DashboardSessionBucket,
} from "@/lib/dashboardSessionBuckets"
import { getTradingWeekday } from "@/lib/formatDate"
import type { SessionBucketStats, SessionPiePoint } from "@/app/components/dashboard/DashboardSessionChart"
import type { WeekdayChartPoint } from "@/app/components/dashboard/DashboardWeekdayChart"

const WEEKDAY_SHORT = ["Mon", "Tue", "Wed", "Thu", "Fri"] as const

const LONG_TO_SHORT: Record<string, (typeof WEEKDAY_SHORT)[number]> = {
  Monday: "Mon",
  Tuesday: "Tue",
  Wednesday: "Wed",
  Thursday: "Thu",
  Friday: "Fri",
}

export function getMarketingDashboardData() {
  const stats = computeDemoDashboardStats(DEMO_TRADES)

  const sessionBuckets = {
    London: { totalTrades: 0, wins: 0, totalPnL: 0 },
    NY: { totalTrades: 0, wins: 0, totalPnL: 0 },
    Asia: { totalTrades: 0, wins: 0, totalPnL: 0 },
  } as Record<DashboardSessionBucket, SessionBucketStats>

  for (const trade of DEMO_TRADES) {
    const bucket = normalizeSessionBucket(trade.session)
    if (!bucket) continue
    const pnl = Number(trade.pnl) || 0
    sessionBuckets[bucket].totalTrades += 1
    sessionBuckets[bucket].totalPnL += pnl
    if (pnl > 0) sessionBuckets[bucket].wins += 1
  }

  const sessionPieData: SessionPiePoint[] = DASHBOARD_SESSION_DISPLAY_ORDER.map(
    (name) => ({
      name,
      value: sessionBuckets[name].totalTrades,
    })
  )

  const weekdayMap: Record<(typeof WEEKDAY_SHORT)[number], number> = {
    Mon: 0,
    Tue: 0,
    Wed: 0,
    Thu: 0,
    Fri: 0,
  }
  const weekdayInsightStats: Record<string, { pnl: number; trades: number }> = {}

  for (const trade of DEMO_TRADES) {
    const source = trade.exit_time ?? trade.entry_time ?? trade.created_at
    const longDay = getTradingWeekday(source)
    if (!longDay) continue
    const pnl = Number(trade.pnl) || 0
    const short = LONG_TO_SHORT[longDay]
    if (short) weekdayMap[short] += pnl

    if (!weekdayInsightStats[longDay]) {
      weekdayInsightStats[longDay] = { pnl: 0, trades: 0 }
    }
    weekdayInsightStats[longDay].pnl += pnl
    weekdayInsightStats[longDay].trades += 1
  }

  const weekdayChart: WeekdayChartPoint[] = WEEKDAY_SHORT.map((day) => ({
    day,
    pnl: weekdayMap[day],
  }))

  const bestSession = DASHBOARD_SESSION_DISPLAY_ORDER.map((name) => {
    const b = sessionBuckets[name]
    const avg = b.totalTrades ? b.totalPnL / b.totalTrades : 0
    const winRate = b.totalTrades ? (b.wins / b.totalTrades) * 100 : 0
    return { name, avg, winRate, trades: b.totalTrades }
  })
    .filter((s) => s.trades > 0)
    .sort((a, b) => b.avg - a.avg)[0]

  const symbolMap = new Map<string, { pnl: number; trades: number; wins: number }>()
  for (const trade of DEMO_TRADES) {
    const ticker = String(trade.ticker || "—")
    const pnl = Number(trade.pnl) || 0
    const cur = symbolMap.get(ticker) ?? { pnl: 0, trades: 0, wins: 0 }
    cur.pnl += pnl
    cur.trades += 1
    if (pnl > 0) cur.wins += 1
    symbolMap.set(ticker, cur)
  }
  const bestSymbol = [...symbolMap.entries()]
    .map(([name, v]) => ({
      name,
      avg: v.trades ? v.pnl / v.trades : 0,
      winRate: v.trades ? (v.wins / v.trades) * 100 : 0,
      trades: v.trades,
    }))
    .sort((a, b) => b.avg - a.avg)[0]

  const bestWeekday = Object.entries(weekdayInsightStats)
    .map(([day, v]) => ({
      day,
      avg: v.trades ? v.pnl / v.trades : 0,
      pnl: v.pnl,
      trades: v.trades,
    }))
    .filter((d) => d.trades > 0)
    .sort((a, b) => b.avg - a.avg)[0]

  return {
    stats,
    sessionBuckets,
    sessionPieData,
    weekdayChart,
    bestSession,
    bestSymbol,
    bestWeekday,
  }
}
