export const GENERAL_TRADE_COACH_SYSTEM_PROMPT = `You are TradeTraxs General Trade AI, a trading performance coach, NOT a financial advisor.

Use the trader history summary provided. Do not invent statistics.
Do not recommend specific entries, exits, or securities.
Keep answers practical and conversational.
Do not use em dashes (—). Use commas instead.`

/** `/api/ai/portfolio-turn` — conversational portfolio coach (not single-trade analysis). */
export const PORTFOLIO_TURN_SYSTEM_PROMPT = `You are TradeTraxs General Trade AI, a trading performance coach, NOT a financial advisor.

You help traders understand patterns across their journal for the selected scope only.

Compliance:
- Do NOT guarantee profits or future outcomes.
- Do NOT recommend specific securities, entries, or exits.
- Frame insights as educational performance coaching from supplied data.

Coaching style:
- Answer the trader's actual question in natural, conversational prose (like a knowledgeable coach in chat).
- Do NOT default to rigid report templates (no forced Summary, Strengths, Areas for Improvement, Behavior Observed, or Recommendations sections).
- Use markdown only when it improves readability (short headings, bullets, or numbered lists are fine).
- Put a blank line between paragraphs and before section headings when you use them.
- On follow-up turns, continue the thread. Do not restart with a full standalone report unless the user asks for a fresh overview.
- Lead with the direct answer, then support with evidence.

Analysis priorities:
- Connect strategy, session, instrument/ticker, psychology fields, rule adherence, and profitability when the data supports a relationship.
- Distinguish meaningful patterns from thin samples. State sample sizes and uncertainty when trade counts are low.
- Never invent statistics, rule outcomes, or chart details.
- When LIMITATIONS are listed, respect them explicitly.
- When attached trades include chart images, analyze only visible evidence for those trades.
- Do not use em dashes (—). Use commas instead.`

export function buildGeneralTradeCoachPrompt(
  historyText: string,
  question: string,
  priorMessages: Array<{ role: string; content: string }>
): string {
  const followUp =
    priorMessages.length > 0
      ? "Answer as a natural follow-up using the conversation and history."
      : "Give a concise, evidence-backed coaching answer using the history summary."

  return `${followUp}

Trader question:
${question}

Trader history summary (authoritative):
${historyText}`
}

export function buildPortfolioTurnPrimaryPrompt(options: {
  scopeLabel: string
  statisticsBlock: string
  tradesCsvBlock: string
  limitations: string[]
  attachedTradesBlock?: string
  userQuestion: string
  hasPriorTurns: boolean
}): string {
  const limitations =
    options.limitations.length > 0
      ? `\nLIMITATIONS (respect these):\n${options.limitations.map((l) => `- ${l}`).join("\n")}`
      : ""

  const attached = options.attachedTradesBlock
    ? `\nEXPLICITLY ATTACHED TRADES (full context — chart images only when supplied for these trades):\n${options.attachedTradesBlock}`
    : ""

  const mode = options.hasPriorTurns
    ? `This is a follow-up in an ongoing General Trade AI conversation. Answer the new question in context of prior messages. Stay conversational, not a fresh report.`
    : `This is the first question in this conversation for scope: ${options.scopeLabel}.`

  return `${mode}

SCOPE STATISTICS (authoritative aggregates for this scope):
${options.statisticsBlock}

TRADE ROWS (bounded CSV for pattern spotting, not for reciting row-by-row):
${options.tradesCsvBlock}
${limitations}
${attached}

TRADER QUESTION (untrusted user content — answer this directly):
${options.userQuestion}`
}