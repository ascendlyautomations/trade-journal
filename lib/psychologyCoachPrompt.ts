export const PSYCHOLOGY_COACH_SYSTEM_PROMPT = `You are TradeTraxs Psychology Coach, a trading-behavior coach, NOT a financial advisor.

CRITICAL RULES:
1. All statistics (win rate, expectancy, P&L, sample sizes, percentages) are provided in the facts payload. NEVER invent, estimate, or recalculate them.
2. If a number is not in the facts, say you do not have enough data, do not guess.
3. Explain patterns in plain, supportive language. Frame recommendations as behavioral guardrails, not guarantees.
4. Do NOT recommend specific securities, entries, exits, or trade signals.
5. Do NOT provide personalized investment advice.
6. Daily check-in free-text notes are NOT included, do not reference them.
7. Associated patterns are correlations, not proof of causation, say so when relevant.
8. Cite sample sizes and both sides of comparisons when you mention a pattern.
9. Writing style: do not use em dashes (—). Use commas instead.

You may answer follow-up questions ONLY about the user's psychology/performance analytics in the facts payload.`

export const PSYCHOLOGY_COACH_INITIAL_SECTIONS = `## Biggest Psychological Insight
## Performance Patterns
## Areas for Improvement
## Recommended Guardrails
## Next Session Focus`

export type PsychologyCoachComparisonSide = {
  label?: string
  sampleLabel?: string
  tradeCount?: number
  winRate?: number | null
  averagePnL?: number | null
  expectancy?: number | null
  reliability?: string
  highlight?: boolean
}

export type PsychologyCoachComparisonFact = {
  id?: string
  category?: string
  title?: string
  headline?: string
  suggestion?: string
  sampleLine?: string
  reliability?: string
  favorableSide?: string
  left?: PsychologyCoachComparisonSide
  right?: PsychologyCoachComparisonSide
}

export type PsychologyCoachFactsPayload = {
  generatedAt?: string | number
  factsHash?: string
  scope?: {
    label?: string
    fingerprint?: string
  }
  reportMeta?: {
    enrichedTradeCount?: number
    checkInMatchedTradeCount?: number
    matchedDayCount?: number
  }
  baseline?: {
    tradeCount?: number
    winRate?: number | null
    expectancy?: number | null
    averagePnL?: number | null
    reliability?: string
  }
  comparisons?: PsychologyCoachComparisonFact[]
  topInsights?: Array<{
    id?: string
    category?: string
    headline?: string
    detail?: string
    sampleSize?: number
    reliability?: string
    winRate?: number | null
    averagePnL?: number | null
    expectancy?: number | null
  }>
  combinedPatterns?: Array<{
    id?: string
    headline?: string
    detail?: string
    sampleSize?: number
    reliability?: string
  }>
  trends?: Array<{
    headline?: string
    detail?: string
    recentSampleSize?: number
    priorSampleSize?: number
    reliability?: string
  }>
  checkInAggregates?: {
    matchedDayCount?: number
    averageSleepHours?: number | null
    averageStress?: number | null
    averageMood?: number | null
    averageConfidence?: number | null
    averageEnergy?: number | null
    averageFocus?: number | null
  }
  tradingRulesCompliance?: {
    adherencePercent?: number | null
    evaluated?: number
    followed?: number
    violated?: number
    topViolationRules?: Array<{
      ruleId?: string
      ruleLabel?: string
      violationCount?: number
      followedWinRate?: number | null
      violatedWinRate?: number | null
    }>
  }
  deterministicCoach?: {
    overview?: string
    doingWell?: string[]
    watchItems?: string[]
    recommendations?: string[]
  }
  guardrailFacts?: Record<string, unknown>
  dataGaps?: string[]
  hasMinimumData?: boolean
}

const INITIAL_MODE_INSTRUCTION = `Produce an evidence-driven psychology coaching brief for this trader.

Use ONLY numbers from the facts JSON. When data is limited, say so briefly in Biggest Psychological Insight and keep other sections short.

Use EXACTLY these markdown headings (one section each):
${PSYCHOLOGY_COACH_INITIAL_SECTIONS}

Section guidance:
- Biggest Psychological Insight: 1-2 sentences with the single strongest supported pattern, include sample sizes and key stats.
- Performance Patterns: 3-5 bullet points with concrete comparisons (win rate, avg P&L, expectancy) where available.
- Areas for Improvement: 2-4 bullet points tied to weaker buckets in comparisons or compliance, no generic trading tips.
- Recommended Guardrails: 2-3 actionable behavioral guardrails supported by guardrailFacts or comparisons.
- Next Session Focus: exactly one sentence, highest-priority focus for the next session.

Do not repeat the same point across sections. No motivational filler.`

const FOLLOW_UP_MODE_INSTRUCTION = `Answer the trader's follow-up in natural conversational prose (no required section headings).

Stay grounded in the facts payload. Reference specific numbers and sample sizes when relevant. If the question cannot be answered from facts, say what is missing.`

export function buildPsychologyCoachUserPrompt(
  facts: PsychologyCoachFactsPayload,
  mode: string
): string {
  const factsJson = JSON.stringify(facts, null, 2)

  const modeInstruction =
    mode === "summary"
      ? `Write a concise personalized psychology summary (2-4 sentences) plus 2-4 bullet observations. Use ONLY numbers from the facts.`
      : mode === "reportSummary"
        ? `Write a brief Psychology Report review the trader can read in under 40 seconds.

Output format (plain text):
1) One short paragraph (2-3 sentences max).
2) Then 2-4 bullet lines from top comparisons/trends only.
3) End with a single line starting with "Focus next:".`
      : mode === "followUp"
        ? FOLLOW_UP_MODE_INSTRUCTION
        : INITIAL_MODE_INSTRUCTION

  return `${modeInstruction}

Structured psychology facts (authoritative, do not recalculate):
${factsJson}`
}

export function buildPsychologyCoachOpenAiMessages(
  facts: PsychologyCoachFactsPayload,
  mode: string,
  priorMessages: Array<{ role: string; content: string }> = []
): Array<{ role: "system" | "user" | "assistant"; content: string }> {
  const trimmed = priorMessages
    .filter(
      (m) =>
        (m.role === "user" || m.role === "assistant") &&
        typeof m.content === "string" &&
        m.content.trim().length > 0
    )
    .slice(-24)

  return [
    { role: "system", content: PSYCHOLOGY_COACH_SYSTEM_PROMPT },
    { role: "user", content: buildPsychologyCoachUserPrompt(facts, mode) },
    ...trimmed.map((m) => ({
      role: m.role as "user" | "assistant",
      content: m.content,
    })),
  ]
}