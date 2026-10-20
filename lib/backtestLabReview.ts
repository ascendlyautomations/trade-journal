import {
  BACKTEST_LAB_NO_STRATEGY,
  backtestStrategyGroupKey,
  type BacktestLabStrategyGroup,
} from "@/lib/backtestLabFilters"

export type BacktestLabReviewFilter = "all" | "reviewed" | "needs_review"

export type BacktestLabDocumentationFilter = "all" | "incomplete"

export type BacktestDocumentationGap =
  | "strategy"
  | "notes"
  | "screenshot"

export function isBacktestTradeReviewed(trade: { reviewed?: unknown }): boolean {
  return trade.reviewed === true
}

/** Explicit queue flag (`reviewed === false`) or not yet marked reviewed. */
export function isBacktestTradeNeedsReview(trade: { reviewed?: unknown }): boolean {
  return trade.reviewed !== true
}

export function isExplicitlyUnreviewedTrade(trade: { reviewed?: unknown }): boolean {
  return trade.reviewed === false
}

function hasText(value: unknown): boolean {
  return String(value ?? "").trim().length > 0
}

export function backtestTradeDocumentationGaps(trade: {
  strategy?: unknown
  notes?: unknown
  top_confluences?: unknown
  psychology_notes?: unknown
  public_description?: unknown
  image_url?: unknown
}): BacktestDocumentationGap[] {
  const gaps: BacktestDocumentationGap[] = []
  if (!hasText(trade.strategy)) gaps.push("strategy")
  const hasNotes =
    hasText(trade.notes) ||
    hasText(trade.top_confluences) ||
    hasText(trade.psychology_notes) ||
    hasText(trade.public_description)
  if (!hasNotes) gaps.push("notes")
  if (!hasText(trade.image_url)) gaps.push("screenshot")
  return gaps
}

export function backtestTradeHasIncompleteDocumentation(trade: {
  strategy?: unknown
  notes?: unknown
  top_confluences?: unknown
  psychology_notes?: unknown
  public_description?: unknown
  image_url?: unknown
}): boolean {
  return backtestTradeDocumentationGaps(trade).length > 0
}

export function formatBacktestDocumentationGapLabels(
  gaps: readonly BacktestDocumentationGap[]
): string {
  if (!gaps.length) return ""
  return gaps
    .map((gap) => {
      if (gap === "strategy") return "strategy"
      if (gap === "notes") return "notes"
      return "screenshot"
    })
    .join(", ")
}

export function backtestStrategyPresetLabels(
  groups: readonly BacktestLabStrategyGroup[]
): string[] {
  return groups
    .filter((g) => g.key !== BACKTEST_LAB_NO_STRATEGY)
    .map((g) => g.label)
}

export function canonicalBacktestStrategyLabel(
  raw: string,
  groups: readonly BacktestLabStrategyGroup[]
): string {
  const trimmed = String(raw ?? "").trim()
  if (!trimmed) return ""
  const key = backtestStrategyGroupKey(trimmed)
  const match = groups.find((g) => g.key === key)
  return match?.label ?? trimmed
}
