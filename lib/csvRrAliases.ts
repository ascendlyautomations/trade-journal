import { parseOptionalRr } from "./tradeRr.ts"

/**
 * Canonical Risk:Reward CSV header aliases.
 * Each entry is normalized via `normalizeHeaderKey` when building the header map.
 * Add new broker/journal column names here only — import logic stays unchanged.
 */
export const CSV_RR_HEADER_ALIASES = [
  "RR",
  "R:R",
  "Risk Reward",
  "Risk:Reward",
  "Risk/Reward",
  "Risk Reward Ratio",
  "Reward Risk",
  "R Multiple",
  "R-Multiple",
  "R Multiple Ratio",
  "R",
  // Legacy / journal-specific
  "reward ratio",
  "realized rr",
  // camelCase export without separator (e.g. riskReward)
  "riskreward",
] as const

/** Import RR only when the CSV cell provides it — never estimate or strip characters. */
export function parseCsvRrValue(raw: string | null | undefined): number | null {
  return parseOptionalRr(raw)
}
