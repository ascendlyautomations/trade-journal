import { averageRrFromTrades } from "./tradeRr.ts"

export type AnalyzeTradeHistoryContext = {
  summaryText: string
}

type TradeLike = Record<string, unknown>

function tradeIdKey(id: unknown): string {
  return String(id ?? "")
}

function hasText(value: unknown): boolean {
  if (value == null) return false
  if (typeof value === "string") return value.trim().length > 0
  if (Array.isArray(value)) return value.length > 0
  return true
}

function formatList(value: unknown): string {
  if (Array.isArray(value)) return value.map(String).join(", ")
  return String(value)
}

function formatDuration(seconds: number | null): string | null {
  if (seconds == null || seconds <= 0) return null
  if (seconds < 60) return `${seconds}s`
  const mins = Math.floor(seconds / 60)
  if (mins < 60) return `${mins}m`
  const hours = Math.floor(mins / 60)
  const remMins = mins % 60
  return remMins > 0 ? `${hours}h ${remMins}m` : `${hours}h`
}

function resolveTradeDurationSeconds(trade: TradeLike): number | null {
  const stored = Number(trade.duration_seconds)
  if (Number.isFinite(stored) && stored > 0) return Math.round(stored)

  const entry = trade.entry_time ?? null
  const exit = trade.exit_time ?? null
  if (entry && exit) {
    const diff = +new Date(String(exit)) - +new Date(String(entry))
    if (Number.isFinite(diff) && diff > 0) return Math.floor(diff / 1000)
  }

  return null
}

function appendIfPresent(lines: string[], label: string, value: unknown) {
  if (!hasText(value)) return
  if (typeof value === "number" && !Number.isFinite(value)) return
  lines.push(`${label}: ${formatList(value)}`)
}

/** Visible trade fields only — omit empty optional journal fields. */
export function formatTradeDataSection(trade: TradeLike): string {
  const lines: string[] = []

  appendIfPresent(lines, "Symbol", trade.ticker)
  appendIfPresent(lines, "Direction", trade.direction)
  if (trade.pnl != null && trade.pnl !== "") {
    lines.push(`P&L: ${trade.pnl}`)
  }
  appendIfPresent(lines, "RR", trade.rr)
  appendIfPresent(lines, "Entry Price", trade.entry_price)
  appendIfPresent(lines, "Exit Price", trade.exit_price)
  appendIfPresent(lines, "Entry Time", trade.entry_time)
  appendIfPresent(lines, "Exit Time", trade.exit_time)
  appendIfPresent(lines, "Trade Date", trade.trade_date ?? trade.date)
  appendIfPresent(lines, "Session", trade.session)
  appendIfPresent(lines, "Strategy", trade.strategy)
  appendIfPresent(lines, "Mode", trade.mode)
  appendIfPresent(lines, "Contracts", trade.contracts)
  appendIfPresent(
    lines,
    "Hold Time",
    formatDuration(resolveTradeDurationSeconds(trade)) ??
      trade.duration_text
  )
  appendIfPresent(lines, "Notes", trade.notes)
  appendIfPresent(
    lines,
    "Confluences / Tags",
    trade.confluences ?? trade.top_confluences
  )
  appendIfPresent(lines, "Mistakes", trade.mistakes)
  appendIfPresent(
    lines,
    "Psychology",
    trade.psychology ?? trade.psychology_notes
  )
  appendIfPresent(lines, "Public Description", trade.public_description)

  if (lines.length === 0) {
    return "Limited structured fields were logged for this trade."
  }

  return lines.join("\n")
}

function computeRecentStreak(trades: TradeLike[]): string | null {
  if (trades.length === 0) return null
  const slice = trades.slice(0, Math.min(5, trades.length))
  const pattern = slice.map((t) =>
    (Number(t.pnl) || 0) > 0 ? "W" : (Number(t.pnl) || 0) < 0 ? "L" : "BE"
  )
  return pattern.join("-")
}

function filterComparableTrades(
  trades: TradeLike[],
  selected: TradeLike,
  key: "ticker" | "session" | "strategy"
): TradeLike[] {
  const raw = selected[key]
  if (!hasText(raw)) return []
  const needle = String(raw).trim().toLowerCase()
  return trades.filter(
    (t) => String(t[key] ?? "").trim().toLowerCase() === needle
  )
}

/** Build historical comparison context from the trader's other trades. */
export function buildAnalyzeTradeHistoryContext(
  allTrades: TradeLike[],
  selectedTradeId: string
): AnalyzeTradeHistoryContext | null {
  const history = allTrades.filter(
    (t) => tradeIdKey(t.id) !== tradeIdKey(selectedTradeId)
  )
  if (history.length === 0) return null

  const selected = allTrades.find(
    (t) => tradeIdKey(t.id) === tradeIdKey(selectedTradeId)
  )
  if (!selected) return null

  const wins = history.filter((t) => (Number(t.pnl) || 0) > 0).length
  const winRate = ((wins / history.length) * 100).toFixed(1)
  const avgRr = averageRrFromTrades(history)
  const durations = history
    .map(resolveTradeDurationSeconds)
    .filter((s): s is number => s != null)
  const avgDuration =
    durations.length > 0
      ? Math.round(
          durations.reduce((sum, s) => sum + s, 0) / durations.length
        )
      : null

  const lines: string[] = [
    `Sample size: ${history.length} prior logged trades (excluding this one).`,
    `Historical win rate: ${winRate}%`,
  ]

  if (avgRr != null) {
    lines.push(`Historical average RR: ${avgRr.toFixed(2)}`)
  }

  if (avgDuration != null) {
    lines.push(
      `Historical average hold time: ${formatDuration(avgDuration) ?? `${avgDuration}s`}`
    )
  }

  const streak = computeRecentStreak(history)
  if (streak) {
    lines.push(`Recent results before this trade (newest first): ${streak}`)
  }

  const sessionTrades = filterComparableTrades(history, selected, "session")
  if (sessionTrades.length >= 3 && hasText(selected.session)) {
    const sessionWins = sessionTrades.filter(
      (t) => (Number(t.pnl) || 0) > 0
    ).length
    lines.push(
      `${selected.session} session (${sessionTrades.length} trades): ${((sessionWins / sessionTrades.length) * 100).toFixed(1)}% win rate`
    )
  }

  const tickerTrades = filterComparableTrades(history, selected, "ticker")
  if (tickerTrades.length >= 3 && hasText(selected.ticker)) {
    const tickerWins = tickerTrades.filter(
      (t) => (Number(t.pnl) || 0) > 0
    ).length
    const tickerAvgRr = averageRrFromTrades(tickerTrades)
    lines.push(
      `${selected.ticker} history (${tickerTrades.length} trades): ${((tickerWins / tickerTrades.length) * 100).toFixed(1)}% win rate${
        tickerAvgRr != null ? `, avg RR ${tickerAvgRr.toFixed(2)}` : ""
      }`
    )
  }

  const strategyTrades = filterComparableTrades(history, selected, "strategy")
  if (strategyTrades.length >= 3 && hasText(selected.strategy)) {
    const strategyWins = strategyTrades.filter(
      (t) => (Number(t.pnl) || 0) > 0
    ).length
    lines.push(
      `Strategy "${selected.strategy}" (${strategyTrades.length} trades): ${((strategyWins / strategyTrades.length) * 100).toFixed(1)}% win rate`
    )
  }

  if (hasStoredComparableRr(selected.rr) && avgRr != null) {
    const tradeRr = Number(selected.rr)
    if (tradeRr >= avgRr) {
      lines.push(
        `This trade's RR (${tradeRr.toFixed(2)}) is at or above the trader's historical average.`
      )
    } else {
      lines.push(
        `This trade's RR (${tradeRr.toFixed(2)}) is below the trader's historical average (${avgRr.toFixed(2)}).`
      )
    }
  }

  const selectedDuration = resolveTradeDurationSeconds(selected)
  if (selectedDuration != null && avgDuration != null) {
    if (selectedDuration >= avgDuration * 1.15) {
      lines.push(
        `Hold time on this trade was longer than the trader's typical duration.`
      )
    } else if (selectedDuration <= avgDuration * 0.85) {
      lines.push(
        `Hold time on this trade was shorter than the trader's typical duration.`
      )
    }
  }

  return { summaryText: lines.join("\n") }
}

function hasStoredComparableRr(value: unknown): boolean {
  if (value == null || value === "") return false
  const n = Number(value)
  return Number.isFinite(n)
}

export const ANALYZE_TRADE_SYSTEM_PROMPT = `You are an experienced trading coach and mentor on TradeTraxs.

Your job is to deliver useful, actionable coaching from the data provided — not to scold the trader for incomplete journaling.

Rules:
- Analyze ALL supplied trade data and historical context first.
- Speak confidently about observable facts (P&L, RR, direction, session, timing, patterns vs history).
- Compare this trade to the trader's own history when historical context is provided.
- Do NOT assume strategy, setup, or intent that is not stated.
- Do NOT fabricate news, economic events, or data that was not supplied.
- Do NOT tell the trader to "journal more", "add more notes", "upload screenshots", or "provide more information" as the main takeaway.
- Missing optional fields must NOT become the focus. Never produce a checklist of missing fields.
- If context is limited, still provide value from what exists (execution quality inferred from RR/P&L, risk discipline, session fit, historical comparisons).
- Tone: balanced, constructive, professional mentor — not a teacher grading homework, not hype, not harsh.
- Be concise and practical. Every section should contain insight, not filler.

Output format (use these exact markdown headings):

## Summary
2–4 sentences on what happened and the main takeaway.

## Strengths
Bullet points for what went well based on available evidence.

## Areas for Improvement
Bullet points for specific, actionable improvements — grounded in data.

## Behavior Observed
What this trade suggests about process, discipline, patience, or risk based on observable facts and history.

## Recommendations
Numbered, concrete next steps the trader can apply on the next similar trade.

## Questions That Could Improve Future Analysis
Optional section — include ONLY if meaningful context is missing.
Ask at most 1–2 thoughtful, conversational follow-up questions that could materially improve future coaching.
Never ask a checklist. Never criticize missing fields.`

export function buildTradeAnalysisPrompt(
  trade: TradeLike,
  historyContext: AnalyzeTradeHistoryContext | null,
  options?: { hasScreenshot?: boolean }
) {
  const tradeData = formatTradeDataSection(trade)
  const historyBlock = historyContext?.summaryText
    ? `\nTRADER HISTORY (same account — use for comparison):\n${historyContext.summaryText}\n`
    : "\nTRADER HISTORY: No prior trades available for comparison.\n"

  const screenshotNote = options?.hasScreenshot
    ? "\nA chart screenshot for this trade is attached to this message. Use it for structure, levels, and execution context when visible.\n"
    : ""

  return `
Analyze this trade like an experienced coach reviewing a student's session.

Use ONLY the trade data, history, and screenshot provided below.
${screenshotNote}
${historyBlock}
THIS TRADE:
${tradeData}

Coaching priorities:
1. Lead with analysis of what IS available (results, RR, timing, session, history comparisons).
2. Reference historical performance when relevant (win rate, avg RR, session/ticker/strategy patterns).
3. Give specific, actionable recommendations — not generic trading advice.
4. Only in "Questions That Could Improve Future Analysis", optionally ask 1–2 conversational questions about missing context that would materially help — never scold or list missing fields.

Do NOT use old section names like "WHAT YOU DID WRONG" or "FINAL VERDICT".
Follow the markdown heading format from your system instructions exactly.
`.trim()
}
