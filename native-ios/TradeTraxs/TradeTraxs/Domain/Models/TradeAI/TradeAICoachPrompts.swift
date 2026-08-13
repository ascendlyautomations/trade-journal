import Foundation

/// Specialized coaching directives for native Trade AI presets.
///
/// The BFF still owns the OpenAI system prompt; these instructions are sent as the
/// latest user turn so each preset produces a short, coach-style reply without
/// changing the `/api/analyze-trade` endpoint.
nonisolated enum TradeAICoachPrompts {
    /// Shared response contract for every preset analysis.
    static let structuredFormatInstructions = """
    For THIS reply only, ignore any prior section names like Summary / Strengths / Areas for Improvement.

    Respond in 100–250 words maximum. No walls of text. No generic ChatGPT filler.
    Every sentence must be specific to THIS trade.

    Use EXACTLY these markdown headings:

    ## Verdict
    One sentence. Start with one of: 🟢 / 🟡 / 🔴 then a blunt coach verdict.
    Examples: "🟢 Strong trade, weak exit." / "🟡 Good idea, poor execution." / "🔴 Low-quality setup."

    ## Biggest Insight
    1–2 sentences. Highest-impact observation only.

    ## Key Improvements
    Maximum 3 short bullet points. Specific and actionable.

    ## Next Trade Focus
    Exactly one sentence — the single highest-priority fix for the next trade.
    """

    static func apiContent(for prompt: TradeAISuggestedPrompt) -> String {
        let focus = focusDirective(for: prompt.id)
        return """
        \(structuredFormatInstructions)

        SPECIALIZED FOCUS FOR THIS REQUEST:
        \(focus)

        Trader selected: \(prompt.title)
        """
    }

    static func apiContentForCustomQuestion(_ question: String) -> String {
        """
        You are an experienced trading coach reviewing one trade.

        Answer the trader's question directly.
        Stay trading-focused, concise, and practical.
        Maximum 250 words unless a slightly longer answer is truly necessary.
        Prefer short paragraphs or tight bullets. No filler. No homework tone.

        Trader question:
        \(question)
        """
    }

    private static func focusDirective(for promptID: String) -> String {
        switch promptID {
        case "analyze":
            return """
            Give a full coach review of this trade using the required structure.
            Lead with the single most valuable insight — do not narrate every field.
            """
        case "winning":
            return """
            Compare this trade ONLY against the trader's winning / higher-quality historical patterns
            (when history is available). Focus on what winners do that this trade did or missed.
            Do not restate the full trade; contrast outcomes, RR, hold time, and session/setup habits.
            """
        case "losing":
            return """
            Compare this trade ONLY against the trader's losing / lower-quality historical patterns
            (when history is available). Call out shared failure modes and how to break them.
            """
        case "mistakes":
            return """
            Focus ONLY on mistakes. Do not pad with praise.
            Prioritize process mistakes (entry timing, exit management, size, plan deviation) over hindsight price action.
            Verdict should reflect mistake severity.
            """
        case "risk":
            return """
            Focus ONLY on risk management: size, RR, stop discipline, asymmetric outcomes, and whether risk matched the setup.
            Ignore psychology and journaling advice unless they directly change risk.
            """
        case "execution":
            return """
            Rate execution quality.
            In Verdict, include an explicit score like "Execution 7/10 — …" after the emoji.
            Explain entry, management, and exit briefly under Biggest Insight / Key Improvements.
            """
        case "emotional":
            return """
            Focus ONLY on psychology / emotional trading signals inferable from data
            (impulse entries, early exits, oversized risk vs RR, revenge patterns vs history).
            Do not invent feelings not supported by evidence.
            """
        case "plan":
            return """
            Evaluate whether the trader followed a coherent trading plan based on available fields
            (strategy tag, session, RR, notes). Call out plan adherence vs improvisation.
            """
        case "journal":
            return """
            Write an objective journal summary of what happened — facts first, then a short coach takeaway.
            Still use the Verdict / Biggest Insight / Key Improvements / Next Trade Focus structure.
            Keep the tone like a clean trade journal entry, not a pep talk.
            """
        case "actions":
            return """
            Give exactly 3 action items for the next similar trade.
            Put them as the Key Improvements bullets (exactly 3).
            Verdict + Biggest Insight should justify why those three matter; Next Trade Focus = the #1 action.
            """
        default:
            return """
            Provide a concise coach review of this trade using the required structure.
            """
        }
    }
}
