import type { PsychologyCoachFacts } from "./types.ts"

export type PsychologyCoachSummary = {
  title: string
  overview: string
  doingWell: string[]
  watchItems: string[]
  recommendations: string[]
}

function buildCoachOverview(facts: PsychologyCoachFacts): string {
  if (!facts.hasMinimumData) {
    return (
      facts.dataGaps[0] ??
      "Log more trades and daily check-ins to unlock personalized coaching."
    )
  }
  const parts: string[] = []
  const best =
    facts.topInsights.find(
      (row) => row.category === "sleep" || row.category === "mentalState"
    ) ?? facts.topInsights[0]
  if (best) {
    parts.push(`Patterns in your check-in data suggest ${best.headline.toLowerCase()}.`)
  } else {
    parts.push("Keep logging trades with psychology tags to sharpen these insights.")
  }
  if (facts.guardrailFacts.consecutiveLossCheckpoint != null) {
    parts.push(
      "Your largest performance drop currently occurs after multiple consecutive losses."
    )
  }
  return parts.join(" ")
}

/** iOS `PsychologyCoachDeterministicCoach.buildSummary`. */
export function buildPsychologyCoachDeterministicSummary(
  facts: PsychologyCoachFacts
): PsychologyCoachSummary {
  const bullets = buildPsychologyCoachSummary(facts)
  return {
    title: "Your Psychology",
    overview: buildCoachOverview(facts),
    doingWell: bullets.doingWell,
    watchItems: bullets.watchItems,
    recommendations: bullets.recommendations,
  }
}

export function buildPsychologyCoachSummary(facts: PsychologyCoachFacts): {
  doingWell: string[]
  watchItems: string[]
  recommendations: string[]
} {
  if (!facts.hasMinimumData) {
    return { doingWell: [], watchItems: [], recommendations: [] }
  }

  const doingWell: string[] = []
  for (const insight of facts.topInsights) {
    const headline = insight.headline.toLowerCase()
    if (
      !headline.includes("in this sample") &&
      !headline.includes("worse") &&
      !headline.includes("less often") &&
      (headline.includes("outperform") ||
        headline.includes("strongest") ||
        headline.includes("stable") ||
        headline.includes("best") ||
        headline.includes("performed better") ||
        headline.includes("won more often"))
    ) {
      doingWell.push(insight.headline)
    }
  }
  for (const trend of facts.trends) {
    const headline = trend.headline.toLowerCase()
    if (headline.includes("improved") || headline.includes("decreased")) {
      doingWell.push(trend.headline)
    }
  }
  for (const combo of facts.combinedPatterns) {
    if (combo.headline.toLowerCase().includes("strongest")) {
      doingWell.push(combo.headline)
    }
  }

  const watchItems = [
    ...facts.topInsights
      .filter((insight) => {
        const headline = insight.headline.toLowerCase()
        return (
          headline.includes("drop") ||
          headline.includes("weaker") ||
          headline.includes("underperform") ||
          headline.includes("worse") ||
          headline.includes("less often") ||
          headline.includes("in this sample")
        )
      })
      .map((insight) => insight.headline),
    ...facts.trends
      .filter((trend) => {
        const headline = trend.headline.toLowerCase()
        return (
          headline.includes("weakened") ||
          headline.includes("increased") ||
          headline.includes("slipped")
        )
      })
      .map((trend) => trend.headline),
  ]

  return {
    doingWell: doingWell.slice(0, 3),
    watchItems: watchItems.slice(0, 4),
    recommendations: buildPsychologyRecommendations(facts).slice(0, 4),
  }
}

export function buildPsychologyRecommendations(facts: PsychologyCoachFacts): string[] {
  const recs: string[] = []
  if (facts.guardrailFacts.consecutiveLossCheckpoint != null) {
    recs.push(
      facts.guardrailFacts.personalLossPause
        ? `Results have been weaker after your pause of ${facts.guardrailFacts.consecutiveLossCheckpoint} consecutive losses.`
        : `Results have been weaker after ${facts.guardrailFacts.consecutiveLossCheckpoint} consecutive losses. That is a result difference, not a reason those trades were taken.`
    )
  }
  if (facts.guardrailFacts.maxTradesDaySoftLimit != null) {
    const limit = facts.guardrailFacts.maxTradesDaySoftLimit
    recs.push(
      facts.guardrailFacts.personalTradeCap
        ? `Trades beyond your daily cap of ${limit} have been weaker than trades within it.`
        : "Later trades in the day have been weaker than your first three. Reviewing whether those extra setups are lower quality may help."
    )
  }
  if (facts.guardrailFacts.lowSleepHoursThreshold != null) {
    recs.push(
      "Be cautious after fewer than 6 hours of sleep. Those sessions have been weaker than better-rested ones."
    )
  }
  if (facts.guardrailFacts.highStressWeaker) {
    recs.push(
      "Reset when stress is high. Lower-stress days have been the stronger ones."
    )
  }
  return recs
}
