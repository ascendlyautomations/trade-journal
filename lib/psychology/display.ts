import { stressLabel } from "../dailyCheckIn/types.ts"

/** iOS `NumberDisplay.ratingOutOfFive`. */
export function formatRatingOutOfFive(value: number): string {
  return `${value.toFixed(1)}/5`
}

/** iOS `NumberDisplay.hours`. */
export function formatHours(value: number): string {
  return `${value.toFixed(1)}h`
}

/** iOS `TraderDailyCheckInStressScale.averageDisplayText`. */
export function stressAverageDisplayText(average: number): string {
  const rounded = Math.min(5, Math.max(1, Math.round(average)))
  return `${formatRatingOutOfFive(average)} · ${stressLabel(rounded)}`
}
