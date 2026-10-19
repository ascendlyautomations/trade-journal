import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"
import {
  psychologyTradeDateKey,
  type PsychologyTradeDateFields,
} from "./tradeDateKey.ts"

export type TradeCheckInContext<T extends PsychologyTradeDateFields> = {
  trade: T
  checkIn: TraderDailyCheckIn | null
  tradeDateKey: string
}

/** Last check-in wins for a duplicate date — same as iOS `uniqueKeysWithValues`. */
export function checkInsByDate(
  checkIns: readonly TraderDailyCheckIn[]
): Map<string, TraderDailyCheckIn> {
  const byDate = new Map<string, TraderDailyCheckIn>()
  for (const checkIn of checkIns) {
    byDate.set(checkIn.checkInDate, checkIn)
  }
  return byDate
}

export function correlateTradesToCheckIns<T extends PsychologyTradeDateFields>(
  trades: readonly T[],
  checkIns: readonly TraderDailyCheckIn[]
): TradeCheckInContext<T>[] {
  const byDate = checkInsByDate(checkIns)
  return trades.map((trade) => {
    const tradeDateKey = psychologyTradeDateKey(trade)
    return {
      trade,
      tradeDateKey,
      checkIn: tradeDateKey ? byDate.get(tradeDateKey) ?? null : null,
    }
  })
}

/** Unique check-ins whose Eastern date appears on at least one trade. */
export function checkInsMatchingTrades<T extends PsychologyTradeDateFields>(
  trades: readonly T[],
  checkIns: readonly TraderDailyCheckIn[]
): TraderDailyCheckIn[] {
  const byDate = checkInsByDate(checkIns)
  const matched = new Map<string, TraderDailyCheckIn>()
  for (const trade of trades) {
    const key = psychologyTradeDateKey(trade)
    const checkIn = key ? byDate.get(key) : undefined
    if (key && checkIn && !matched.has(key)) {
      matched.set(key, checkIn)
    }
  }
  return [...matched.values()]
}
