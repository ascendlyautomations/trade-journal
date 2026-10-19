import type { TraderDailyCheckIn } from "../../dailyCheckIn/types.ts"
import { enrichPsychologyTrades } from "./enrich.ts"
import { psychologyTradeMetrics, qualifiesForDashboardCard } from "./metrics.ts"
import type { PsychologyCoachTrendFact, PsychologyReportTrade } from "./types.ts"

const RECENT_TRADE_WINDOW = 30
const MINIMUM_PRIOR_TRADES = 20

function followedPlanRate(trades: readonly PsychologyReportTrade[]): number {
  const tagged = trades.filter((trade) => trade.followedPlan != null)
  if (!tagged.length) return 0
  return tagged.filter((trade) => trade.followedPlan === true).length / tagged.length
}

function emotionShare(trades: readonly PsychologyReportTrade[], emotion: string): number {
  const tagged = trades
    .map((trade) => String(trade.emotion ?? "").trim())
    .filter(Boolean)
  if (!tagged.length) return 0
  return (
    tagged.filter((value) => value.toLowerCase() === emotion.toLowerCase()).length /
    tagged.length
  )
}

export function analyzePsychologyTrends(
  trades: readonly PsychologyReportTrade[],
  checkIns: readonly TraderDailyCheckIn[]
): PsychologyCoachTrendFact[] {
  const sorted = [...trades].sort((a, b) => a.entryAtMs - b.entryAtMs)
  if (sorted.length < RECENT_TRADE_WINDOW + MINIMUM_PRIOR_TRADES) return []

  const recent = sorted.slice(-RECENT_TRADE_WINDOW)
  const prior = sorted.slice(0, -RECENT_TRADE_WINDOW)
  const facts: PsychologyCoachTrendFact[] = []

  const recentRate = followedPlanRate(recent)
  const priorRate = followedPlanRate(prior)
  if (
    recent.length >= 15 &&
    prior.length >= MINIMUM_PRIOR_TRADES &&
    Math.abs(recentRate - priorRate) >= 0.08
  ) {
    facts.push({
      id: "trend.discipline",
      headline:
        recentRate > priorRate
          ? "Plan adherence has improved recently"
          : "Plan adherence has slipped recently",
      detail: `Recent ${recent.length} trades: ${Math.round(recentRate * 100)}% followed plan vs prior history: ${Math.round(priorRate * 100)}%`,
      recentSampleSize: recent.length,
      priorSampleSize: prior.length,
      reliability: recent.length >= 25 ? "developing" : "earlySignal",
    })
  }

  const recentFOMO = emotionShare(recent, "FOMO")
  const priorFOMO = emotionShare(prior, "FOMO")
  if (
    recent.length >= 15 &&
    prior.length >= MINIMUM_PRIOR_TRADES &&
    Math.abs(recentFOMO - priorFOMO) >= 0.08
  ) {
    facts.push({
      id: "trend.fomo",
      headline:
        recentFOMO < priorFOMO
          ? "FOMO-tagged trades decreased recently"
          : "FOMO-tagged trades increased recently",
      detail: `Recent: ${Math.round(recentFOMO * 100)}% FOMO vs prior: ${Math.round(priorFOMO * 100)}% of tagged trades`,
      recentSampleSize: recent.length,
      priorSampleSize: prior.length,
      reliability: "developing",
    })
  }

  const recentEnriched = enrichPsychologyTrades(recent, checkIns)
  const priorEnriched = enrichPsychologyTrades(prior, checkIns)
  const recentAfterTwo = recentEnriched.filter((row) => row.consecutiveLossesBefore >= 2)
  const priorAfterTwo = priorEnriched.filter((row) => row.consecutiveLossesBefore >= 2)
  if (recentAfterTwo.length >= 8 && priorAfterTwo.length >= 8) {
    const recentM = psychologyTradeMetrics(recentAfterTwo.map((row) => row.trade))
    const priorM = psychologyTradeMetrics(priorAfterTwo.map((row) => row.trade))
    if (
      qualifiesForDashboardCard(recentM.reliability) &&
      qualifiesForDashboardCard(priorM.reliability)
    ) {
      const recentExp = recentM.expectancy ?? recentM.averagePnL ?? 0
      const priorExp = priorM.expectancy ?? priorM.averagePnL ?? 0
      const delta = recentExp - priorExp
      if (Math.abs(delta) >= 10) {
        facts.push({
          id: "trend.afterLosses",
          headline:
            delta > 0
              ? "Performance after consecutive losses has improved"
              : "Performance after consecutive losses has weakened",
          detail: `Recent after 2+ losses avg $${Math.round(recentExp)} vs prior $${Math.round(priorExp)} expectancy`,
          recentSampleSize: recentAfterTwo.length,
          priorSampleSize: priorAfterTwo.length,
          reliability: "developing",
        })
      }
    }
  }

  return facts
}
