import {
  filterTradesForLeaderboardAccountType,
  filterTradesForLeaderboardWindow,
  type LeaderboardAccountTypeFilter,
  type TradeForLeaderboard,
} from "./leaderboardChart.ts"
import { filterTradesForLeaderboardDateRange } from "./weeklyLeaderboardPeriod.ts"
export type ExploreWeeklyTopCategory = "pnl" | "rr" | "winRate"

export type ExploreWeeklyTopPerformerPick = {
  category: ExploreWeeklyTopCategory
  userId: string
  metricLabel: string
  totalPnl?: number
  avgRR?: number
  winRatePct?: number
}

type WeeklyUserAgg = {
  userId: string
  totalPnl: number
  tradeCount: number
  winCount: number
  rrSum: number
  rrCount: number
}

const ACCOUNT: LeaderboardAccountTypeFilter = "all"

function num(v: unknown): number {
  const n = Number(v)
  return Number.isFinite(n) ? n : 0
}

function rrValue(raw: unknown): number | null {
  if (raw === null || raw === undefined) return null
  if (typeof raw === "string" && raw.trim() === "") return null
  const n = Number(raw)
  return Number.isFinite(n) ? n : null
}

function aggregateWeeklyUsers(trades: TradeForLeaderboard[]): WeeklyUserAgg[] {
  const map = new Map<string, WeeklyUserAgg>()

  for (const trade of trades) {
    const userId = String(trade.user_id ?? "").trim()
    if (!userId) continue

    let row = map.get(userId)
    if (!row) {
      row = {
        userId,
        totalPnl: 0,
        tradeCount: 0,
        winCount: 0,
        rrSum: 0,
        rrCount: 0,
      }
      map.set(userId, row)
    }

    const pnl = num(trade.pnl)
    row.tradeCount += 1
    row.totalPnl += pnl
    if (pnl > 0) row.winCount += 1

    const rr = rrValue(trade.rr)
    if (rr !== null) {
      row.rrSum += rr
      row.rrCount += 1
    }
  }

  return Array.from(map.values())
}

function avgRR(row: WeeklyUserAgg): number | null {
  return row.rrCount > 0 ? row.rrSum / row.rrCount : null
}

function winRatePct(row: WeeklyUserAgg): number | null {
  if (row.tradeCount <= 0) return null
  return (row.winCount / row.tradeCount) * 100
}

function pickMax<T>(
  rows: T[],
  value: (row: T) => number | null,
  eligible: (row: T) => boolean,
  tieKey: (row: T) => string
): T | null {
  let best: T | null = null
  let bestValue = Number.NEGATIVE_INFINITY

  for (const row of rows) {
    if (!eligible(row)) continue
    const v = value(row)
    if (v === null || !Number.isFinite(v)) continue
    if (v > bestValue) {
      bestValue = v
      best = row
    } else if (v === bestValue && best !== null) {
      if (tieKey(row) < tieKey(best)) best = row
    }
  }

  return best
}

export function pickWeeklyTopPerformersInRange(
  trades: TradeForLeaderboard[],
  start: Date,
  end: Date
): ExploreWeeklyTopPerformerPick[] {
  const windowTrades = filterTradesForLeaderboardDateRange(
    filterTradesForLeaderboardAccountType(trades, ACCOUNT),
    start,
    end
  )
  const users = aggregateWeeklyUsers(windowTrades)
  return pickWeeklyTopPerformersFromAggregates(users)
}

function pickWeeklyTopPerformersFromAggregates(
  users: WeeklyUserAgg[]
): ExploreWeeklyTopPerformerPick[] {
  const picks: ExploreWeeklyTopPerformerPick[] = []

  const pnlWinner = pickMax(
    users,
    (u) => u.totalPnl,
    (u) => u.tradeCount > 0,
    (u) => u.userId
  )
  if (pnlWinner) {
    picks.push({
      category: "pnl",
      userId: pnlWinner.userId,
      metricLabel: "Net P&L",
      totalPnl: pnlWinner.totalPnl,
    })
  }

  const rrWinner = pickMax(
    users,
    (u) => avgRR(u),
    (u) => avgRR(u) !== null && u.rrCount > 0,
    (u) => u.userId
  )
  if (rrWinner) {
    picks.push({
      category: "rr",
      userId: rrWinner.userId,
      metricLabel: "Avg R:R",
      avgRR: avgRR(rrWinner)!,
    })
  }

  const winWinner = pickMax(
    users,
    (u) => winRatePct(u),
    (u) => u.tradeCount > 0,
    (u) => u.userId
  )
  if (winWinner) {
    picks.push({
      category: "winRate",
      userId: winWinner.userId,
      metricLabel: "Win Rate",
      winRatePct: winRatePct(winWinner)!,
    })
  }

  return picks
}

/** Rolling 7-day window (legacy callers / tests). */
export function pickExploreWeeklyTopPerformers(
  trades: TradeForLeaderboard[],
  now = new Date()
): ExploreWeeklyTopPerformerPick[] {
  const windowTrades = filterTradesForLeaderboardWindow(
    filterTradesForLeaderboardAccountType(trades, ACCOUNT),
    "7D",
    now
  )
  return pickWeeklyTopPerformersFromAggregates(aggregateWeeklyUsers(windowTrades))
}
