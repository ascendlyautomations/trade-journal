import type { ScorecardReliability } from "./types.ts"

export function resolveScorecardReliability(sampleSize: number): ScorecardReliability {
  if (sampleSize < 5) return "insufficient"
  if (sampleSize <= 9) return "earlySignal"
  if (sampleSize <= 29) return "developing"
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

export function isDevelopingOrStrong(reliability: ScorecardReliability): boolean {
  return reliability === "developing" || reliability === "strong"
}

export function clampScore(value: number): number {
  return Math.max(0, Math.min(100, Math.round(value)))
}

export function formatPercent(value: number, digits = 0): string {
  return `${(value * 100).toFixed(digits)}%`
}
