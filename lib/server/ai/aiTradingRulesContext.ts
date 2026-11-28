import type { SupabaseClient } from "@supabase/supabase-js"
import type { Database } from "@/lib/database.types"
import { loadTradingPreferenceBundle } from "@/lib/analytics/tradingPreferencesStore"
import type { PreferenceRuleContext } from "@/lib/analytics/preferenceCompliance"
import {
  buildTradingRulesComplianceAnalytics,
  complianceTradesFromRows,
  type RuleViolationEvent,
  type TradingRulesComplianceAnalytics,
} from "@/lib/analytics/tradingRulesComplianceAnalytics"

type Db = SupabaseClient<Database>

function formatViolations(events: RuleViolationEvent[], limit: number): string {
  const violations = events.slice(0, limit)
  if (violations.length === 0) {
    return "No evaluated rule violations in scope (unevaluated checks omitted)."
  }
  return violations
    .map(
      (v) =>
        `- ${v.ruleLabel} (${v.level})${v.tradeId ? ` trade=${v.tradeId}` : ""}: ${v.summary}`
    )
    .join("\n")
}

function formatImpacts(analytics: TradingRulesComplianceAnalytics): string {
  const lines = analytics.impacts
    .filter((row) => row.sufficientSample && row.summary)
    .slice(0, 8)
    .map((row) => `- ${row.ruleLabel}: ${row.summary}`)
  return lines.length > 0
    ? lines.join("\n")
    : "Insufficient paired samples for rule impact comparisons in this scope."
}

/** Same bundle + analytics pipeline as Dashboard Trading Rules. */
export async function loadTradingRulesAnalyticsForUser(
  db: Db,
  userId: string,
  tradeRows: readonly Record<string, unknown>[]
): Promise<TradingRulesComplianceAnalytics | null> {
  const bundle = await loadTradingPreferenceBundle(db, userId)
  const context: PreferenceRuleContext = {
    revisions: bundle.revisions,
    global: bundle.global,
    overrides: bundle.overrides,
  }
  const trades = complianceTradesFromRows(tradeRows)
  if (trades.length === 0) return null
  return buildTradingRulesComplianceAnalytics(trades, context)
}

export function formatTradingRulesContextBlock(
  analytics: TradingRulesComplianceAnalytics | null,
  options?: { tradeId?: string; violationLimit?: number }
): string {
  if (!analytics) {
    return "TRADING RULES: No trades in scope to evaluate compliance."
  }

  const score = analytics.score
  const adherence =
    score.adherencePercent != null
      ? `${score.adherencePercent}% (${score.followed} followed, ${score.violated} violated, ${score.unevaluated} unevaluated)`
      : "insufficient evaluated checks"

  let block = `TRADING RULES COMPLIANCE (Dashboard-equivalent engine):
Historical revisions: ${analytics.usesHistoricalRevisions ? "yes" : "no"}
Adherence: ${adherence}
${score.explanation}

Recent violations in scope:
${formatViolations(analytics.violations, options?.violationLimit ?? 12)}

Rule impact summaries (correlation only):
${formatImpacts(analytics)}`

  if (options?.tradeId) {
    const tradeViolations = formatViolations(
      analytics.violations.filter((v) => v.tradeId === options.tradeId),
      8
    )
    block += `\n\nThis trade:\n${tradeViolations}`
  }

  return block
}