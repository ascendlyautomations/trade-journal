import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { psychologyTradeDateKey } from "../tradeDateKey.ts"
import { pnlSign } from "./metrics.ts"
import type { PsychologyEnrichedTrade, PsychologyReportTrade } from "./types.ts"

export function enrichPsychologyTrades(
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[]
): PsychologyEnrichedTrade[] {
  const byDate = new Map<string, TraderDailyCheckIn>()
  for (const checkIn of checkIns) {
    byDate.set(checkIn.checkInDate, checkIn)
  }

  const chronological = [...trades].sort((a, b) => a.entryAtMs - b.entryAtMs)
  let consecutiveLosses = 0
  let consecutiveWins = 0
  const dayCounts = new Map<string, number>()

  return chronological.map((trade) => {
    const dayKey = psychologyTradeDateKey(trade)
    const nextNumber = (dayCounts.get(dayKey) ?? 0) + 1
    dayCounts.set(dayKey, nextNumber)

    const snapshot: PsychologyEnrichedTrade = {
      trade,
      dailyCheckIn: dayKey ? byDate.get(dayKey) ?? null : null,
      consecutiveLossesBefore: consecutiveLosses,
      consecutiveWinsBefore: consecutiveWins,
      tradeNumberInDay: nextNumber,
      previousTradeWasLoss: consecutiveLosses > 0,
    }

    const sign = pnlSign(trade)
    if (sign === "win") {
      consecutiveWins += 1
      consecutiveLosses = 0
    } else if (sign === "loss") {
      consecutiveLosses += 1
      consecutiveWins = 0
    }

    return snapshot
  })
}

export function resolveSleepBand(
  hours: number | null | undefined
): "<5h" | "5–6h" | "6–7h" | "7–8h" | "8–9h" | "9h+" | null {
  if (hours == null || !Number.isFinite(hours)) return null
  if (hours < 5) return "<5h"
  if (hours < 6) return "5–6h"
  if (hours < 7) return "6–7h"
  if (hours < 8) return "7–8h"
  if (hours <= 9) return "8–9h"
  return "9h+"
}

export const SLEEP_BANDS = ["<5h", "5–6h", "6–7h", "7–8h", "8–9h", "9h+"] as const

export function resolveLossBucket(
  losses: number
): "0 prior losses" | "1 prior loss" | "2 prior losses" | "3+ prior losses" {
  if (losses <= 0) return "0 prior losses"
  if (losses === 1) return "1 prior loss"
  if (losses === 2) return "2 prior losses"
  return "3+ prior losses"
}

export function resolveSequenceBucket(
  number: number
): "Trade #1" | "Trade #2" | "Trade #3" | "Trade #4" | "Trade #5+" {
  if (number === 1) return "Trade #1"
  if (number === 2) return "Trade #2"
  if (number === 3) return "Trade #3"
  if (number === 4) return "Trade #4"
  return "Trade #5+"
}
