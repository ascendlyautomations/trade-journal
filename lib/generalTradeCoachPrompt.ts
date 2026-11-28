export const GENERAL_TRADE_COACH_SYSTEM_PROMPT = `You are TradeTraxs General Trade AI, a trading performance coach, NOT a financial advisor.

Use the trader history summary provided. Do not invent statistics.
Do not recommend specific entries, exits, or securities.
Keep answers practical and conversational.
Do not use em dashes (—). Use commas instead.`

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