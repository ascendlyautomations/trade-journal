import { formatCurrency } from "./formatCurrency.ts"

function formatRatio(value: unknown): string {
  if (value === null || value === undefined) return "—"
  if (typeof value === "string" && value.trim() === "") return "—"
  const number = Number(value)
  if (!Number.isFinite(number)) return "—"
  return number.toLocaleString(undefined, {
    minimumFractionDigits: 0,
    maximumFractionDigits: 2,
  })
}

export type MobileWebDashboardTone = "neutral" | "positive" | "negative"

export type MobileWebDashboardChip = {
  id: string
  label: string
  value: string
  tone: MobileWebDashboardTone
}

function profitFactorTone(
  profitFactor: number | null | undefined
): MobileWebDashboardTone {
  if (profitFactor == null || !Number.isFinite(profitFactor)) return "neutral"
  return profitFactor >= 1 ? "positive" : "negative"
}

/** Native KPI strip order: Win Rate, Profit Factor, Avg RR, Avg Max R, Trades, Expectancy. */
export function buildMobileWebDashboardMetricChips(input: {
  winRate: number
  profitFactor: number | null | undefined
  avgRR: number | null
  avgMaxRrReached: number | null | undefined
  totalTrades: number
  expectancy: number | null | undefined
}): MobileWebDashboardChip[] {
  return [
    {
      id: "win",
      label: "Win Rate",
      value: `${input.winRate.toFixed(1)}%`,
      tone: "neutral",
    },
    {
      id: "pf",
      label: "Profit Factor",
      value: formatRatio(input.profitFactor),
      tone: profitFactorTone(input.profitFactor),
    },
    {
      id: "rr",
      label: "Avg RR",
      value: formatRatio(input.avgRR),
      tone: "neutral",
    },
    {
      id: "maxRr",
      label: "Avg Max R",
      value: formatRatio(input.avgMaxRrReached),
      tone: "neutral",
    },
    {
      id: "trades",
      label: "Trades",
      value: input.totalTrades.toLocaleString(),
      tone: "neutral",
    },
    {
      id: "expectancy",
      label: "Expectancy",
      value:
        input.expectancy == null || !Number.isFinite(input.expectancy)
          ? "—"
          : formatCurrency(input.expectancy),
      tone: moneyTone(input.expectancy),
    },
  ]
}

/** Native performance cards: Avg Win, Avg Loss, Best Trade, Biggest Loss, Max Drawdown, Payouts. */
export function buildMobileWebDashboardPerformanceCards(input: {
  avgWin: number
  avgLoss: number
  bestTrade: number
  biggestLoss: number
  maxDrawdown: number
  payoutsTotal?: number | null
}): MobileWebDashboardChip[] {
  const payouts = input.payoutsTotal
  return [
    {
      id: "avgWin",
      label: "Avg Win",
      value: formatCurrency(input.avgWin),
      tone: "positive",
    },
    {
      id: "avgLoss",
      label: "Avg Loss",
      value: formatCurrency(input.avgLoss),
      tone: "negative",
    },
    {
      id: "best",
      label: "Best Trade",
      value: formatCurrency(input.bestTrade),
      tone: "positive",
    },
    {
      id: "worst",
      label: "Biggest Loss",
      value: formatCurrency(input.biggestLoss),
      tone: "negative",
    },
    {
      id: "dd",
      label: "Max Drawdown",
      value: formatCurrency(input.maxDrawdown),
      tone: input.maxDrawdown > 0 ? "negative" : "neutral",
    },
    {
      id: "payouts",
      label: "Payouts",
      value:
        payouts == null || !Number.isFinite(payouts)
          ? "—"
          : formatCurrency(payouts),
      tone: payouts != null && payouts > 0 ? "positive" : "neutral",
    },
  ]
}

export function lastEquityPointValue(
  points: readonly { equity: number }[] | null | undefined
): number | null {
  if (!points || points.length === 0) return null
  const last = points[points.length - 1]
  return last && Number.isFinite(last.equity) ? last.equity : null
}

export function mobileWebDashboardHeroTitle(
  usesAccountBalance: boolean
): "Account Value" | "Equity" {
  return usesAccountBalance ? "Account Value" : "Equity"
}

export function mobileWebDashboardHourBars(
  hourlyMap: Record<number, number> | null | undefined
): Array<{ hour: number; value: number }> {
  const source = hourlyMap ?? {}
  return Array.from({ length: 24 }, (_, hour) => {
    const raw = Number(source[hour])
    return { hour, value: Number.isFinite(raw) ? raw : 0 }
  })
}

export function mobileWebDashboardHourBarsHaveSignal(
  bars: readonly { value: number }[]
): boolean {
  return bars.some((bar) => Math.abs(bar.value) > 0.01)
}

export function moneyTone(value: number | null | undefined): MobileWebDashboardTone {
  if (value == null || !Number.isFinite(value)) return "neutral"
  if (value > 0) return "positive"
  if (value < 0) return "negative"
  return "neutral"
}
