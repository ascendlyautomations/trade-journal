import {
  getTradingDayKey,
  resolveTradingTimeSourceForKey,
} from "./formatDate.ts"

export const MOBILE_WEB_CALENDAR_MONTH_ABBREV = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
] as const

export type MobileWebCalendarYearMonth = {
  month: number
  abbreviation: string
  netPnl: number
  tradeCount: number
  tradingDayCount: number
  isFuture: boolean
}

export type MobileWebCalendarYearOverview = {
  year: number
  netPnl: number
  tradeCount: number
  tradingDayCount: number
  winRate: number | null
  bestMonth: number | null
  bestMonthPnl: number | null
  months: MobileWebCalendarYearMonth[]
}

type CalendarYearTrade = {
  pnl?: unknown
  created_at?: string | null
  date?: string | null
  entry_time?: string | null
  exit_time?: string | null
}

function tradePnl(trade: CalendarYearTrade): number {
  const n = Number(trade.pnl)
  return Number.isFinite(n) ? n : 0
}

export function compactCalendarYearPnl(value: number): string {
  if (!Number.isFinite(value) || value === 0) return "$0"
  const sign = value < 0 ? "-" : "+"
  const abs = Math.abs(value)
  if (abs >= 10_000) {
    return `${sign}$${Math.round(abs / 1000)}k`
  }
  if (abs >= 1000) {
    const k = abs / 1000
    const text = k >= 10 ? String(Math.round(k)) : k.toFixed(1).replace(/\.0$/, "")
    return `${sign}$${text}k`
  }
  return `${sign}$${Math.round(abs)}`
}

/**
 * Year overview from already-loaded journal trades.
 * Uses Eastern Time trading-day keys (6pm ET rollover) — no extra fetches.
 */
export function buildMobileWebCalendarYearOverview(
  trades: readonly CalendarYearTrade[],
  year: number,
  now: Date = new Date()
): MobileWebCalendarYearOverview {
  const nowKey = getTradingDayKey(now)
  const nowYear = nowKey ? Number(nowKey.slice(0, 4)) : now.getFullYear()
  const nowMonth = nowKey ? Number(nowKey.slice(5, 7)) : now.getMonth() + 1

  const monthPnls = Array.from({ length: 12 }, () => 0)
  const monthTrades = Array.from({ length: 12 }, () => 0)
  const monthDays = Array.from({ length: 12 }, () => new Set<string>())
  let wins = 0
  let counted = 0

  for (const trade of trades) {
    const source = resolveTradingTimeSourceForKey(trade)
    if (!source) continue
    const key = getTradingDayKey(source)
    if (!key) continue
    const [yk, mk] = key.split("-").map(Number)
    if (yk !== year || !mk || mk < 1 || mk > 12) continue
    const pnl = tradePnl(trade)
    const idx = mk - 1
    monthPnls[idx] += pnl
    monthTrades[idx] += 1
    monthDays[idx].add(key)
    counted += 1
    if (pnl > 0) wins += 1
  }

  const months: MobileWebCalendarYearMonth[] = MOBILE_WEB_CALENDAR_MONTH_ABBREV.map(
    (abbreviation, idx) => {
      const month = idx + 1
      const isFuture =
        year > nowYear || (year === nowYear && month > nowMonth)
      return {
        month,
        abbreviation,
        netPnl: isFuture ? 0 : monthPnls[idx],
        tradeCount: isFuture ? 0 : monthTrades[idx],
        tradingDayCount: isFuture ? 0 : monthDays[idx].size,
        isFuture,
      }
    }
  )

  let netPnl = 0
  let tradeCount = 0
  let tradingDayCount = 0
  let bestMonth: number | null = null
  let bestMonthPnl: number | null = null
  for (const card of months) {
    if (card.isFuture) continue
    netPnl += card.netPnl
    tradeCount += card.tradeCount
    tradingDayCount += card.tradingDayCount
    if (card.tradeCount === 0 && card.tradingDayCount === 0) continue
    if (bestMonthPnl == null || card.netPnl > bestMonthPnl) {
      bestMonthPnl = card.netPnl
      bestMonth = card.month
    }
  }

  return {
    year,
    netPnl,
    tradeCount,
    tradingDayCount,
    winRate: counted > 0 ? (wins / counted) * 100 : null,
    bestMonth,
    bestMonthPnl,
    months,
  }
}
