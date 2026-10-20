export type TradingReportMonthRef = {
  year: number
  month: number
}

export type TradingYearlyMonthMetrics = {
  year: number
  month: number
  monthLabel: string
  netPnl: number
  tradeCount: number
  winRate: number | null
  monthRef: TradingReportMonthRef
}

export type TradingYearlyMonthRow = {
  month: number
  monthLabel: string
  availability:
    | { kind: "upcoming" }
    | { kind: "available"; metrics: TradingYearlyMonthMetrics }
}

export type TradingYearlyReportMetrics = {
  netPnl: number
  tradeCount: number
  winRate: number | null
  profitFactor: number | null
  averageWinner: number | null
  averageLoser: number | null
  averageRr: number | null
  expectancy: number | null
  bestTrade: number | null
  worstTrade: number | null
  bestDayLabel: string | null
  bestDayPnl: number | null
  worstDayLabel: string | null
  worstDayPnl: number | null
  maxDrawdown: number
  winningDays: number
  losingDays: number
  winCount: number
  lossCount: number
}

export type TradingYearlyMonthlyBar = {
  label: string
  value: number
}

export type TradingYearlyReport = {
  year: number
  title: string
  dateRangeLabel: string
  periodStartIso: string
  periodEndIso: string
  generatedAt: number
  executiveSummary: string
  metrics: TradingYearlyReportMetrics
  monthRows: TradingYearlyMonthRow[]
  monthlyPnLBars: TradingYearlyMonthlyBar[]
  strongestMonth: TradingYearlyMonthMetrics | null
  weakestMonth: TradingYearlyMonthMetrics | null
  equityCurve: { date: string; equity: number }[]
}
