import type { ScorecardCategoryResult } from "@/lib/scorecard"
import { normalizeAIGeneratedText } from "@/lib/normalizeAIGeneratedText"

export const PLAN_ADHERENCE_SCORE_LABEL = "Plan-Adherence Score (Phase 1)"

export const PHASE1_SCORE_EXPLAINER =
  "Phase 1 numbers come from explicit plan-adherence tags only. Consistency scores post-loss plan adherence; Discipline scores overall plan adherence among tagged trades. Risk Management and Psychology are informational in Phase 1, they do not affect this composite."

/** Scorecard / insight template copy (not user-authored). */
export function scorecardDisplayProse(text: string): string {
  return normalizeAIGeneratedText(text)
}

/** Dashboard row / summary label for a category (never a bare dash for unscored Phase 1 categories). */
export function categoryPhase1RowLabel(category: ScorecardCategoryResult): string {
  if (category.id === "risk") return "Metrics only (Phase 1)"
  if (category.id === "psychology") return "Insights only (Phase 1)"
  if (category.score != null) return String(category.score)
  return "—"
}

/** Detail page subtitle fragment for category score line. */
export function categoryPhase1DetailScoreLabel(category: ScorecardCategoryResult): string {
  if (category.id === "risk") return "Metrics only (Phase 1)"
  if (category.id === "psychology") return "Insights only (Phase 1)"
  if (category.score != null) return `${category.score}/100`
  return "Insufficient evidence"
}
