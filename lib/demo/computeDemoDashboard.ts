import type { EquityChartPoint } from "@/app/components/dashboard/DashboardEquityCurve"
import { getTradingWeekday } from "@/lib/formatDate"
import { averageRrFromTrades } from "@/lib/tradeRr"

export type DemoDashboardStats = {
  totalTrades: number
  winRate: number
  avgRR: number | null
  totalPnL: number
  avgWin: number
  bestTrade: number
  avgLoss: number
  biggestLoss: number
  bestDay: number
  worstDay: number
  equityCurve: EquityChartPoint[]
  profitFactor: number
  currentStreak: number
  avgDay: number
  consistency: number
  hourlyMap: Record<number, number>
  weekdayPnl: Record<string, number>
  expectancy: number
  maxWinStreak: number
  maxLossStreak: number
  currentStreakType: "win" | "loss" | "even" | null
}

export function computeDemoDashboardStats(trades: any[]): DemoDashboardStats {
  const pnls = trades.map((t) => Number(t.pnl) || 0)
  const totalTrades = trades.length
  const wins = pnls.filter((p) => p > 0)
  const losses = pnls.filter((p) => p < 0)
  const totalPnL = pnls.reduce((s, p) => s + p, 0)
  const winRate = totalTrades ? (wins.length / totalTrades) * 100 : 0
  const avgWin = wins.length ? wins.reduce((s, p) => s + p, 0) / wins.length : 0
  const avgLoss = losses.length
    ? losses.reduce((s, p) => s + p, 0) / losses.length
    : 0
  const bestTrade = wins.length ? Math.max(...wins) : 0
  const biggestLoss = losses.length ? Math.min(...losses) : 0

  const dailyPnl = new Map<string, number>()
  const hourlyMap: Record<number, number> = {}
  const weekdayPnl: Record<string, number> = {}

  for (const trade of trades) {
    const pnl = Number(trade.pnl) || 0
    const exitMs = new Date(trade.exit_time ?? trade.created_at).getTime()
    const dayKey = new Date(exitMs).toISOString().slice(0, 10)
    dailyPnl.set(dayKey, (dailyPnl.get(dayKey) ?? 0) + pnl)

    const hour = new Date(trade.entry_time ?? trade.exit_time).getHours()
    hourlyMap[hour] = (hourlyMap[hour] ?? 0) + pnl

    const weekday = getTradingWeekday(trade.exit_time ?? trade.created_at)
    if (weekday) {
      weekdayPnl[weekday] = (weekdayPnl[weekday] ?? 0) + pnl
    }
  }

  const dayTotals = [...dailyPnl.values()]
  const bestDay = dayTotals.length ? Math.max(...dayTotals) : 0
  const worstDay = dayTotals.length ? Math.min(...dayTotals) : 0

  const chronological = [...trades].sort(
    (a, b) =>
      new Date(a.exit_time ?? a.created_at).getTime() -
      new Date(b.exit_time ?? b.created_at).getTime()
  )
  let running = 0
  const equityCurve: EquityChartPoint[] = chronological.map((trade) => {
    running += Number(trade.pnl) || 0
    return {
      date: new Date(trade.exit_time ?? trade.created_at).toISOString(),
      equity: running,
    }
  })

  const grossWin = wins.reduce((s, p) => s + p, 0)
  const grossLoss = Math.abs(losses.reduce((s, p) => s + p, 0))
  const profitFactor = grossLoss > 0 ? grossWin / grossLoss : grossWin > 0 ? 99 : 0

  let currentStreak = 0
  let currentStreakType: "win" | "loss" | "even" | null = null
  let maxWinStreak = 0
  let maxLossStreak = 0
  let winRun = 0
  let lossRun = 0

  for (const trade of chronological) {
    const pnl = Number(trade.pnl) || 0
    if (pnl > 0) {
      winRun += 1
      lossRun = 0
      maxWinStreak = Math.max(maxWinStreak, winRun)
    } else if (pnl < 0) {
      lossRun += 1
      winRun = 0
      maxLossStreak = Math.max(maxLossStreak, lossRun)
    }
  }

  const lastPnl = chronological.length
    ? Number(chronological[chronological.length - 1].pnl) || 0
    : 0
  if (lastPnl > 0) {
    currentStreakType = "win"
    currentStreak = winRun
  } else if (lastPnl < 0) {
    currentStreakType = "loss"
    currentStreak = lossRun
  } else {
    currentStreakType = "even"
    currentStreak = 0
  }

  const tradingDays = dailyPnl.size || 1
  const avgDay = totalPnL / tradingDays
  const positiveDays = [...dailyPnl.values()].filter((v) => v > 0).length
  const consistency = tradingDays ? (positiveDays / tradingDays) * 100 : 0
  const expectancy = totalTrades ? totalPnL / totalTrades : 0

  return {
    totalTrades,
    winRate,
    avgRR: averageRrFromTrades(trades),
    totalPnL,
    avgWin,
    bestTrade,
    avgLoss,
    biggestLoss,
    bestDay,
    worstDay,
    equityCurve,
    profitFactor,
    currentStreak,
    avgDay,
    consistency,
    hourlyMap,
    weekdayPnl,
    expectancy,
    maxWinStreak,
    maxLossStreak,
    currentStreakType,
  }
}
