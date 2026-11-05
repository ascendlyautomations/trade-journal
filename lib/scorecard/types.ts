import type { PsychologySampleReliability } from "../psychology/reports/types.ts"
import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"

export type ScorecardCategoryId =
  | "consistency"
  | "risk"
  | "discipline"
  | "psychology"

export type ScorecardReliability = PsychologySampleReliability

export type ScorecardSubMetric = {
  id: string
  label: string
  value: string
  explanation: string
  sampleSize: number
  sampleLabel: string
}

export type ScorecardCategoryResult = {
  id: ScorecardCategoryId
  title: string
  weight: number
  /** null when insufficient data to score fairly */
  score: number | null
  coveragePercent: number
  reliability: ScorecardReliability
  eligible: boolean
  subMetrics: ScorecardSubMetric[]
  strengths: string[]
  weaknesses: string[]
  dataGaps: string[]
}

export type ScorecardOverallContribution = {
  id: ScorecardCategoryId
  title: string
  score: number
  /** Design weight before renormalization (0–1). */
  nominalWeight: number
  /** Share of the composite after renormalization (0–1). */
  effectiveWeight: number
}

export type ScorecardOverallResult = {
  score: number | null
  status: "ready" | "building" | "unavailable"
  statusMessage: string
  coveragePercent: number
  reliability: ScorecardReliability
  tradeCount: number
  tradingDayCount: number
  /** Categories included in the overall score, with effective weights. */
  contributions: ScorecardOverallContribution[]
  /** Nominal weight sum (0–1) of categories that contributed — below 1 means partial composite. */
  nominalWeightIncluded: number
}

export type ScorecardResult = {
  scopeLabel: string
  generatedAtMs: number
  overall: ScorecardOverallResult
  categories: ScorecardCategoryResult[]
}

export type ScorecardTrade = {
  id: string
  pnl: number
  rr: number | null
  maxRrReached: number | null
  realizedRr: number | null
  followedPlan: boolean | null
  mistakeType: string | null
  confidence: number | null
  executionRating: number | null
  entryTimeMs: number
  /** Dashboard futures session day (6 PM ET rollover). */
  tradingDayKey: string | null
  /** Eastern calendar day for check-in matching (no session rollover). */
  psychologyDayKey: string | null
}

export type ScorecardAnalyticsContext = {
  periodTradingDayCount: number
  maxDrawdown: number
  avgWin: number
  avgLoss: number
  totalTrades: number
  /** Win rate after 3 consecutive losses (0–1), if detectable */
  postTripleLossWinRate: number | null
}

export type ScorecardBuildInput = {
  scopeLabel: string
  trades: readonly ScorecardTrade[]
  checkIns: readonly TraderDailyCheckIn[]
  analytics: ScorecardAnalyticsContext
}

export const SCORECARD_CATEGORY_WEIGHTS: Record<ScorecardCategoryId, number> = {
  consistency: 0.25,
  risk: 0.25,
  discipline: 0.2,
  psychology: 0.3,
}

export const SCORECARD_MIN_TRADES_OVERALL = 20
export const SCORECARD_MIN_TRADING_DAYS_OVERALL = 5
/** Minimum nominal weight sum (0–1) across scored categories to show a composite overall score. */
export const SCORECARD_MIN_NOMINAL_WEIGHT_OVERALL = 0.45
/** Minimum number of scored categories for a composite overall score. */
export const SCORECARD_MIN_SCORED_CATEGORIES_OVERALL = 2
