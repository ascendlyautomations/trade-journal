/**
 * Mirror of SQL `analytics_mode_effective` / profile_statistics_resolve_account_mode.
 */

export type AnalyticsModeEffective =
  | "evaluation"
  | "funded"
  | "live"
  | "sim"
  | "backtest"
  | "unknown"

export function analyticsModeEffective(input: {
  accountMode?: string | null
  accountType?: string | null
  tradeMode?: string | null
}): AnalyticsModeEffective {
  const raw = [
    input.accountMode,
    input.accountType,
    input.tradeMode,
  ]
    .map((v) => (v ?? "").trim())
    .find((v) => v.length > 0)

  if (!raw) return "unknown"

  switch (raw.toLowerCase()) {
    case "eval":
    case "evaluation":
      return "evaluation"
    case "funded":
      return "funded"
    case "sim":
    case "replay":
      return "sim"
    case "backtest":
      return "backtest"
    case "live":
      return "live"
    default:
      return "unknown"
  }
}
