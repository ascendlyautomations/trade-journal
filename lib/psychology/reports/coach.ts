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
      headline.includes("outperform") ||
      headline.includes("strongest") ||
      headline.includes("stable") ||
      headline.includes("best")
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
          headline.includes("underperform")
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
      `Consider using ${facts.guardrailFacts.consecutiveLossCheckpoint} consecutive losses as a checkpoint before taking another trade — historically your results weaken after this point.`
    )
  }
  if (facts.guardrailFacts.maxTradesDaySoftLimit != null) {
    recs.push(
      `Your first ${facts.guardrailFacts.maxTradesDaySoftLimit} trades currently outperform later trades. Consider reviewing whether additional setups are becoming lower quality.`
    )
  }
  if (facts.guardrailFacts.lowSleepHoursThreshold != null) {
    recs.push(
      "Your historical results are weaker below 6 hours of sleep. Consider treating low-sleep sessions as higher-risk days."
    )
  }
  for (const insight of facts.topInsights) {
    if (
      insight.category === "mentalState" &&
      insight.headline.toLowerCase().includes("stress")
    ) {
      recs.push(
        "High-stress days correlate with weaker results in your journal. A brief reset before the next trade may help."
      )
      break
    }
  }
  return recs
}
