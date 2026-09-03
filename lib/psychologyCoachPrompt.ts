export const PSYCHOLOGY_COACH_SYSTEM_PROMPT = `You are TradeTraxs Psychology Coach — a trading-behavior coach, NOT a financial advisor.

CRITICAL RULES:
1. All statistics (win rate, expectancy, P&L, sample sizes, percentages) are provided in the facts payload. NEVER invent, estimate, or recalculate them.
2. If a number is not in the facts, say you do not have enough data — do not guess.
3. Explain patterns in plain, supportive language. Frame recommendations as behavioral guardrails, not guarantees.
4. Do NOT recommend specific securities, entries, exits, or trade signals.
5. Do NOT provide personalized investment advice.
6. Daily check-in free-text notes are NOT included — do not reference them.
7. Associated patterns are correlations, not proof of causation — say so when relevant.
8. Keep responses concise and professional.

You may answer follow-up questions ONLY about the user's psychology/performance analytics in the facts payload.`

export type PsychologyCoachFactsPayload = {
  generatedAt?: string
  factsHash?: string
  baseline?: {
    tradeCount?: number
    winRate?: number | null
    expectancy?: number | null
    averagePnL?: number | null
    reliability?: string
  }
  topInsights?: Array<{
    id?: string
    category?: string
    headline?: string
    detail?: string
    sampleSize?: number
    reliability?: string
  }>
  combinedPatterns?: Array<{
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
  guardrailFacts?: Record<string, unknown>
  dataGaps?: string[]
  hasMinimumData?: boolean
}

export function buildPsychologyCoachUserPrompt(
  facts: PsychologyCoachFactsPayload,
  mode: string,
  messages: Array<{ role: string; content: string }> = []
): string {
  const factsJson = JSON.stringify(facts, null, 2)
  const modeInstruction =
    mode === "summary"
      ? "Write a concise personalized psychology summary (2-4 sentences) plus 2-4 bullet observations. Use ONLY numbers from the facts."
      : mode === "reportSummary"
        ? "Write an AI Psychology Summary for this report period. Explain the most important supported patterns in 2-4 paragraphs. Use ONLY numbers from the facts. Include comparisons when present in trends."
      : mode === "explain"
        ? "Explain the user's top psychology patterns in plain language. Include practical behavioral guardrails where supported by facts."
        : "Answer the user's follow-up question using ONLY the facts below."

  const history =
    messages.length > 0
      ? `\n\nPrior conversation:\n${messages.map((m) => `${m.role}: ${m.content}`).join("\n")}`
      : ""

  return `${modeInstruction}

Structured psychology facts (authoritative — do not recalculate):
${factsJson}${history}`
}
