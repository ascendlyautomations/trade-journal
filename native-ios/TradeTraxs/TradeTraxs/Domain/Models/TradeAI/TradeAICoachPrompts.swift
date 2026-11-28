import Foundation

/// Specialized coaching directives for native Trade AI presets.
///
/// The BFF uses `TRADE_AI_TURN_SYSTEM_PROMPT`; these instructions are sent as
/// `openaiContent` on the latest user turn so each preset shapes the reply.
nonisolated enum TradeAICoachPrompts {
  static func apiContent(for prompt: TradeAISuggestedPrompt) -> String {
    let focus = focusDirective(for: prompt.id)
    return """
    \(responseFormat(for: prompt.id))

    SPECIALIZED FOCUS FOR THIS REQUEST:
    \(focus)

    Trader selected: \(prompt.title)
    """
  }

  static func apiContentForCustomQuestion(_ question: String) -> String {
    """
    RESPONSE FORMAT (this reply only):
    Answer the trader's question directly in natural coach prose (max ~280 words unless depth is clearly needed).
    Do NOT force Verdict / Biggest Insight headings unless they genuinely help readability.

    Readable output (Markdown when substantive):
    - Start with a concise direct answer.
    - Use ## headings, "-" bullets, numbered lists, and **bold** for key stats and actions.
    - Put a blank line between paragraphs and before headings.

    Trader question:
    \(question)
    """
  }

  private static func responseFormat(for promptID: String) -> String {
    switch promptID {
    case "mistakes", "actions":
      return improvementResponseFormat
    case "journal":
      return journalResponseFormat
    default:
      return standardCoachResponseFormat
    }
  }

  private static let standardCoachResponseFormat = """
  RESPONSE FORMAT (this reply only):
  Ignore any prior templates like Summary / Strengths / Areas for Improvement.

  Respond in 120–280 words. No walls of text. Do not recap journal statistics unless a number directly supports your point.

  Use EXACTLY these markdown headings on their own lines with a blank line before each section body:

  ## Verdict
  One sentence. Start with 🟢 or 🟡 or 🔴 then a blunt coach verdict.

  ## Biggest Insight
  1–2 sentences. Highest-impact observation only.

  ## Key Improvements
  Up to 3 bullet lines starting with "- ".

  ## Next Trade Focus
  Exactly one sentence.
  """

  private static let improvementResponseFormat = """
  RESPONSE FORMAT (this reply only):
  Use EXACTLY these markdown headings (no Verdict section). Blank line between sections.

  ## Biggest Insight
  1–2 short paragraphs. The single highest-impact improvement theme for THIS trade.

  ## Key Improvements
  Number exactly 3 items. Each item MUST be one line in this form:
  1. **Short title** — What to change, why it matters for this trade, and how to apply it next time.

  ## Next Trade Focus
  One sentence — the #1 habit to practice on the next similar trade.

  When a chart screenshot is attached, anchor at least one numbered improvement in visible entry, stop, target, or structure.
  """

  private static let journalResponseFormat = """
  RESPONSE FORMAT (this reply only):
  Use these headings with blank lines between sections:

  ## Verdict
  One neutral sentence summarizing outcome quality.

  ## Biggest Insight
  Factual session summary in 2–3 sentences.

  ## Key Improvements
  Up to 2 factual process notes (bullets with "- ").

  ## Next Trade Focus
  One sentence takeaway for the next session.
  """

  private static func focusDirective(for promptID: String) -> String {
    switch promptID {
    case "analyze":
      return """
      Give a full coach review of this trade.
      Lead with the sharpest insight; do not narrate every field.
      Combine chart evidence (when present), psychology check-in, rules evaluation, and history briefly.
      """
    case "winning":
      return """
      Compare this trade ONLY against the trader's winning / higher-quality historical patterns
      (when history is available). Focus on what winners do that this trade did or missed.
      """
    case "losing":
      return """
      Compare this trade ONLY against the trader's losing / lower-quality historical patterns
      (when history is available). Call out shared failure modes and how to break them.
      """
    case "mistakes":
      return """
      Improvement coaching only — what could have been done better on THIS trade.
      Prioritize execution, management, risk, and plan deviation over repeating P&L or win-rate stats.
      Explain what to improve, why it matters, and how to apply it next time.
      Never invent chart details or assume unevaluated trading rules were followed.
      """
    case "risk":
      return """
      Focus ONLY on risk management: size, RR, stop discipline, asymmetric outcomes, and whether risk matched the setup.
      """
    case "execution":
      return """
      Rate execution quality.
      In Verdict, include an explicit score like "Execution 7/10," after the emoji when scoreable from data and/or chart.
      Cover entry, management, and exit under Biggest Insight / Key Improvements.
      """
    case "emotional":
      return """
      Focus ONLY on psychology / emotional process inferable from data (impulse entries, early exits, size vs RR).
      Do not invent feelings not supported by evidence.
      """
    case "plan":
      return """
      Evaluate plan and rules adherence from strategy, session, RR, notes, and evaluated TRADING RULES data only.
      Do not assume compliance when rules were not evaluated.
      """
    case "journal":
      return """
      Write an objective journal summary of what happened, facts first, then a short coach takeaway.
      """
    case "actions":
      return """
      Give exactly 3 action items for the next similar trade using the numbered Key Improvements format.
      Biggest Insight should justify why those three matter.
      """
    default:
      return """
      Provide concise, trade-specific coaching aligned with the trader's question.
      """
    }
  }
}