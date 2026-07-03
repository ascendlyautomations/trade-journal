export type TradingReportPeriodKey =
  | "weekly_this"
  | "weekly_last"
  | "monthly_this"
  | "monthly_last"

export type TradingReportKind = "weekly" | "monthly"

export type TradingReportMetrics = {
  netPnl: number
  winRate: number
  averageRr: number | null
  profitFactor: number | null
  tradesTaken: number
  bestDayLabel: string | null
  bestDayPnl: number | null
  worstDayLabel: string | null
  worstDayPnl: number | null
  bestSessionLabel: string | null
  bestSessionPnl: number | null
  worstSessionLabel: string | null
  worstSessionPnl: number | null
  mostTradedSymbol: string | null
  averageHoldTimeSeconds: number | null
}

/** Deterministic report — `summarySource` allows future AI replacement. */
export type TradingReport = {
  periodKey: TradingReportPeriodKey
  kind: TradingReportKind
  title: string
  dateRangeLabel: string
  periodStartIso: string
  periodEndIso: string
  generatedAt: number
  executiveSummary: string
  metrics: TradingReportMetrics
  strengths: string[]
  opportunities: string[]
  recommendations: string[]
  bestTradeId: string | null
  keyTakeaway: string
  summarySource: "deterministic" | "ai"
}

export type TradingReportsSnapshot = {
  reports: Record<TradingReportPeriodKey, TradingReport>
  computedAt: number
}

export type NewTradingReportBadge =
  | { kind: "weekly"; label: "🟢 New Weekly Report" }
  | { kind: "monthly"; label: "🟣 Monthly Report Ready" }
  | null
