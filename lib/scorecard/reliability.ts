import type { ScorecardReliability } from "./types.ts"

export function resolveScorecardReliability(sampleSize: number): ScorecardReliability {
  if (sampleSize < 3) return "insufficient"
  if (sampleSize <= 7) return "earlySignal"
  if (sampleSize <= 19) return "developing"
  return "strong"
}

export function reliabilityLabel(reliability: ScorecardReliability): string {
  switch (reliability) {
    case "insufficient":
      return "Insufficient data"
    case "earlySignal":
      return "Early signal"
    case "developing":
      return "Developing"
    case "strong":
      return "Strong signal"
  }
}

export function clampScore(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value)))
}

export function formatPercent(value: number, digits = 0): string {
  return `${(value * 100).toFixed(digits)}%`
}
