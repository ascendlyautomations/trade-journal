import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"

export const PSYCHOLOGY_REPORT_TRADE_CAP = 500

export const PSYCHOLOGY_REPORT_TEMPLATES = [
  "weekly",
  "monthly",
  "sleepPerformance",
  "discipline",
  "emotions",
  "afterLosses",
  "mentalState",
  "tradeFrequency",
] as const

export type PsychologyReportTemplate = (typeof PSYCHOLOGY_REPORT_TEMPLATES)[number]

export type PsychologyReportPeriodRef = {
  template: PsychologyReportTemplate
  periodID: string
}

export type PsychologySampleReliability =
  | "insufficient"
  | "earlySignal"
  | "developing"
  | "strong"

export type PsychologyInsightCategory =
  | "sleep"
  | "mentalState"
  | "conviction"
  | "discipline"
  | "emotion"
  | "afterLosses"
  | "tradeFrequency"
  | "combined"

export type PsychologyGroupMetrics = {
  tradeCount: number
  winCount: number
  lossCount: number
  winRate: number | null
  totalPnL: number
  averagePnL: number | null
  expectancy: number | null
  averageRR: number | null
  profitFactor: number | null
  reliability: PsychologySampleReliability
}

export type PsychologyInsightCard = {
  id: string
  category: PsychologyInsightCategory
  sectionTitle: string
  headline: string
  detail: string
  sampleSize: number
  reliability: PsychologySampleReliability
  rankingScore: number
}

export type PsychologyAnalyticsGroupRow = {
  id: string
  label: string
  metrics: PsychologyGroupMetrics
  highlight: boolean
}

export type PsychologyAnalyticsSection = {
  id: string
  title: string
  subtitle: string | null
  groups: PsychologyAnalyticsGroupRow[]
  footnote: string | null
}

export type PsychologyAnalyticsReport = {
  generatedAt: number
  baseline: PsychologyGroupMetrics
  dashboardCards: PsychologyInsightCard[]
  sections: PsychologyAnalyticsSection[]
  enrichedTradeCount: number
  checkInMatchedTradeCount: number
}

export type PsychologyReportTrade = {
  id: string
  entryAtMs: number
  entry_time: string
  created_at?: string | null
  pnl: number
  rr: number | null
  mode?: string | null
  account_type?: string | null
  emotion: string | null
  confidence: number | null
  followedPlan: boolean | null
  executionRating: number | null
}

export type PsychologyEnrichedTrade = {
  trade: PsychologyReportTrade
  dailyCheckIn: TraderDailyCheckIn | null
  consecutiveLossesBefore: number
  consecutiveWinsBefore: number
  tradeNumberInDay: number
  previousTradeWasLoss: boolean
}

export type PsychologyReportCheckInSummary = {
  checkInCount: number
  averageSleepHours: number | null
  averageSleepQuality: number | null
  averageMorningRating: number | null
  averageStress: number | null
  averageEnergy: number | null
  averageFocus: number | null
}

export type PsychologyReportTradingPsychology = {
  followedPlanRate: number | null
  averageConviction: number | null
  mostCommonEmotion: string | null
  fomoTradeCount: number
  frustratedTradeCount: number
  averageExecutionRating: number | null
}

export type PsychologyReportBehaviorSummary = {
  averageTradesPerDay: number | null
  afterTwoLossesWinRate: number | null
  afterTwoLossesBaselineWinRate: number | null
  earlyTradeAvgPnL: number | null
  lateTradeAvgPnL: number | null
}

export type PsychologyReportComparison = {
  headline: string
  detail: string
  reliability: string
}

export type PsychologyReportMetricRow = {
  label: string
  value: string
}

export type PsychologyReportSection = {
  id: string
  title: string
  subtitle: string | null
  bullets: string[]
  metrics: PsychologyReportMetricRow[]
}

export type PsychologyReport = {
  periodRef: PsychologyReportPeriodRef
  reportID: string
  title: string
  dateRangeLabel: string
  periodStartIso: string
  periodEndIso: string
  generatedAt: number
  factsHash: string
  checkInSummary: PsychologyReportCheckInSummary
  tradingPsychology: PsychologyReportTradingPsychology
  behavior: PsychologyReportBehaviorSummary
  performance: PsychologyGroupMetrics
  comparisons: PsychologyReportComparison[]
  doingWell: string[]
  watchItems: string[]
  sections: PsychologyReportSection[]
}

export type PsychologyCoachFactInsight = {
  id: string
  category: string
  headline: string
  detail: string
  sampleSize: number
  reliability: string
}

export type PsychologyCoachTrendFact = {
  id: string
  headline: string
  detail: string
  recentSampleSize: number
  priorSampleSize: number
  reliability: string
}

export type PsychologyCoachGuardrailFacts = {
  consecutiveLossCheckpoint: number | null
  consecutiveLossWinRateAfter: number | null
  consecutiveLossBaselineWinRate: number | null
  lowSleepHoursThreshold: number | null
  lowSleepExpectancy: number | null
  maxTradesDaySoftLimit: number | null
  lateTradeAveragePnL: number | null
  earlyTradeAveragePnL: number | null
}

export type PsychologyCoachFacts = {
  generatedAt: number
  factsHash: string
  baseline: {
    tradeCount: number
    winRate: number | null
    expectancy: number | null
    averagePnL: number | null
    reliability: string
  }
  topInsights: PsychologyCoachFactInsight[]
  combinedPatterns: PsychologyCoachFactInsight[]
  trends: PsychologyCoachTrendFact[]
  guardrailFacts: PsychologyCoachGuardrailFacts
  dataGaps: string[]
  hasMinimumData: boolean
}

export const EMPTY_PSYCHOLOGY_METRICS: PsychologyGroupMetrics = {
  tradeCount: 0,
  winCount: 0,
  lossCount: 0,
  winRate: null,
  totalPnL: 0,
  averagePnL: null,
  expectancy: null,
  averageRR: null,
  profitFactor: null,
  reliability: "insufficient",
}
