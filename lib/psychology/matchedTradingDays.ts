import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import { isCompleteCheckIn } from "../dailyCheckIn/validation.ts"
import { checkInsByDate } from "./correlate.ts"
import {
  psychologyTradeDateKey,
  type PsychologyTradeDateFields,
} from "./tradeDateKey.ts"

export type MatchedTradingDay = {
  dateKey: string
  checkIn: TraderDailyCheckIn
  dailyPnL: number
  tradeCount: number
  winCount: number
  lossCount: number
  winRate: number | null
}

export type TradeWithPnL = PsychologyTradeDateFields & {
  pnl?: string | number | null
}

function readTradePnL(trade: TradeWithPnL): number {
  const raw = trade.pnl
  const value = typeof raw === "string" ? Number.parseFloat(raw) : Number(raw)
  return Number.isFinite(value) ? value : 0
}

/**
 * One row per Eastern calendar day that has both a complete check-in and ≥1 trade
 * in the filtered set. Daily P&L is the sum of trade P&L for that day (never double-counted).
 */
export function buildMatchedTradingDays(
  trades: readonly TradeWithPnL[],
  checkIns: readonly TraderDailyCheckIn[]
): MatchedTradingDay[] {
  const byDate = checkInsByDate(checkIns.filter(isCompleteCheckIn))
  const dayTrades = new Map<
    string,
    { pnls: number[]; checkIn: TraderDailyCheckIn }
  >()

  for (const trade of trades) {
    const key = psychologyTradeDateKey(trade)
    if (!key) continue
    const checkIn = byDate.get(key)
    if (!checkIn) continue
    const bucket = dayTrades.get(key) ?? { pnls: [], checkIn }
    bucket.pnls.push(readTradePnL(trade))
    dayTrades.set(key, bucket)
  }

  const rows: MatchedTradingDay[] = []
  for (const [dateKey, { pnls, checkIn }] of dayTrades) {
    const winCount = pnls.filter((p) => p > 0).length
    const lossCount = pnls.filter((p) => p < 0).length
    const tradeCount = pnls.length
    const dailyPnL = pnls.reduce((sum, p) => sum + p, 0)
    rows.push({
      dateKey,
      checkIn,
      dailyPnL,
      tradeCount,
      winCount,
      lossCount,
      winRate: tradeCount > 0 ? winCount / tradeCount : null,
    })
  }

  rows.sort((a, b) => a.dateKey.localeCompare(b.dateKey))
  return rows
}
