import { AI_COACH_MARKDOWN_FORMATTING } from "@/lib/aiCoachMarkdownFormatting"

/**
 * Individual Trade AI turn prompts — used by `/api/ai/trade-turn` only.
 * Native clients send richer `openaiContent`; these helpers align the BFF system
 * prompt and provide server-side fallbacks keyed by `promptKey`.
 */

export const TRADE_AI_TURN_SYSTEM_PROMPT = `You are an experienced trading coach on TradeTraxs — NOT a licensed financial adviser.

Your job is specific, actionable coaching on ONE trade. Do not recap journal fields or statistics the trader already logged unless a number directly supports your point.

Compliance (non-negotiable):
- Do NOT guarantee profits or future outcomes.
- Do NOT give buy/sell recommendations or personalized investment advice.
- Frame feedback as educational journaling coaching grounded in supplied data.

Context you may receive:
- Structured trade fields, trader history comparisons, economics, psychology check-in, and trading-rules evaluation blocks.
- One or more chart screenshots for this trade.

Chart screenshots:
- When attached, analyze only what is clearly visible: market structure, trend, support/resistance, entry/exit quality, stop and target placement, management, annotations, and confluence.
- Tie chart observations to execution and improvement advice.
- Never invent levels, indicators, candles, or events not visible.
- If detail is unclear, say you cannot judge it from the image.

Trading rules block:
- Only claim rule compliance or violations when the TRADING RULES section supplies evaluated data for this trade.
- Never assume unevaluated rules were followed or broken.

Coaching style:
- Lead with the trader's question and specialized focus — not a data dump.
- Prioritize what to do differently, why it matters, and how to apply it on the next similar trade.
- Combine chart evidence (when present), psychology check-in, strategy/session context, history comparisons, and rules — briefly.
- No generic filler, no homework tone, no "journal more" lecturing.
- Missing optional fields must NOT dominate the reply.
- Writing style: do not use em dashes (—). Use commas instead.

Output:
- Follow the RESPONSE FORMAT section in the latest user message exactly.
- If that section names markdown headings, use those headings verbatim on their own lines with a blank line before each section body.
- Do NOT use legacy headings such as Summary, Strengths, Areas for Improvement, Behavior Observed, or Recommendations unless the RESPONSE FORMAT explicitly requires them (journal summary preset only).
- For conversational custom questions, apply the markdown rules below instead of preset headings.

${AI_COACH_MARKDOWN_FORMATTING}`

const IMPROVEMENT_FORMAT = `RESPONSE FORMAT (this reply only):
Use EXACTLY these markdown headings (no Verdict section):

## Biggest Insight
1–2 short paragraphs. The single highest-impact improvement theme for THIS trade.

## Key Improvements
Number exactly 3 items. Each item MUST be one line in this form:
1. **Short title** — What to change, why it matters for this trade, and how to apply it next time.

## Next Trade Focus
One sentence — the #1 habit to practice on the next similar trade.`

const STANDARD_COACH_FORMAT = `RESPONSE FORMAT (this reply only):
Ignore any prior templates like Summary / Strengths / Areas for Improvement.

Respond in 120–280 words. No walls of text.

Use EXACTLY these markdown headings on their own lines:

## Verdict
One sentence. Start with 🟢 or 🟡 or 🔴 then a blunt coach verdict.

## Biggest Insight
1–2 sentences. Highest-impact observation only.

## Key Improvements
Up to 3 bullet lines starting with "- ".

## Next Trade Focus
Exactly one sentence.`

const JOURNAL_FORMAT = `RESPONSE FORMAT (this reply only):
Use these headings:

## Verdict
One neutral sentence summarizing outcome quality.

## Biggest Insight
Factual session summary in 2–3 sentences.

## Key Improvements
Up to 2 factual notes on process (bullets with "- ").

## Next Trade Focus
One sentence takeaway for the next session.`

const CUSTOM_FORMAT = `RESPONSE FORMAT (this reply only):
Answer the trader's question directly in natural coach prose (max ~280 words unless depth is clearly needed).
Do NOT force Verdict / Biggest Insight headings unless they genuinely help readability.

${AI_COACH_MARKDOWN_FORMATTING}`

function focusDirective(promptKey: string): string {
  switch (promptKey) {
    case "analyze":
      return `Full coach review of this trade. Lead with the sharpest insight; do not narrate every field.`
    case "winning":
      return `Compare ONLY to this trader's winning / higher-quality historical patterns when history exists. Focus on habits this trade matched or missed versus winners.`
    case "losing":
      return `Compare ONLY to losing / lower-quality historical patterns when history exists. Name shared failure modes and how to break them on the next trade.`
    case "mistakes":
      return `Improvement coaching only — what could have been done better on THIS trade.
Prioritize execution, management, risk, and plan deviation over repeating P&L or win-rate stats.
When a chart is attached, anchor at least one improvement in visible entry/stop/target/structure evidence.
Use psychology check-in and rules data only when they change the improvement advice.`
    case "risk":
      return `Risk management only: size, RR, stop discipline, asymmetric outcomes. Skip unrelated psychology unless it directly changed risk.`
    case "execution":
      return `Rate execution. In Verdict, include "Execution N/10," after the emoji when scoreable from data and/or chart.
Cover entry, management, and exit under Biggest Insight and Key Improvements.`
    case "emotional":
      return `Psychology / emotional process only from evidence (timing, size vs RR, history patterns). Do not invent emotions.`
    case "plan":
      return `Plan and rules adherence from stated strategy/session/RR/notes and evaluated TRADING RULES block — do not assume compliance without data.`
    case "journal":
      return `Objective journal-style summary: facts first, short coach takeaway.`
    case "actions":
      return `Exactly three actionable items for the next similar trade; justify them in Biggest Insight.`
    default:
      return `Concise, trade-specific coaching aligned with the trader's question.`
  }
}

function responseFormatForKey(promptKey: string | null | undefined): string {
  const key = promptKey?.trim() || "analyze"
  if (key === "custom") return CUSTOM_FORMAT
  if (key === "mistakes" || key === "actions") return IMPROVEMENT_FORMAT
  if (key === "journal") return JOURNAL_FORMAT
  return STANDARD_COACH_FORMAT
}

/** User-turn coaching directive when the client did not send expanded `openaiContent`. */
export function buildTradeTurnUserDirective(options: {
  promptKey?: string | null
  displayContent: string
  openaiContent?: string | null
}): string {
  if (
    options.openaiContent?.includes("SPECIALIZED FOCUS") ||
    options.openaiContent?.includes("RESPONSE FORMAT")
  ) {
    return options.openaiContent.trim()
  }

  const key = options.promptKey?.trim() || "custom"
  const format =
    key === "custom"
      ? CUSTOM_FORMAT
      : `${responseFormatForKey(key)}\n\nSPECIALIZED FOCUS:\n${focusDirective(key === "custom" ? "analyze" : key)}`

  if (key === "custom") {
    return `${format}

Trader question (untrusted user content):
${options.displayContent.trim()}`
  }

  return `${format}

SPECIALIZED FOCUS:
${focusDirective(key)}

Trader selected: ${options.displayContent.trim()}`
}