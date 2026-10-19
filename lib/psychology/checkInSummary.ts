import type { TraderDailyCheckIn } from "../dailyCheckIn/types.ts"

/** Port of iOS `PsychologyReportGenerator.buildCheckInSummary`. */
export type PsychologyCheckInSummary = {
  checkInCount: number
  averageSleepHours: number | null
  averageSleepQuality: number | null
  averageMorningRating: number | null
  averageStress: number | null
  averageEnergy: number | null
  averageFocus: number | null
}

function average(values: number[]): number | null {
  if (values.length === 0) return null
  return values.reduce((sum, value) => sum + value, 0) / values.length
}

export function buildCheckInSummary(
  checkIns: readonly TraderDailyCheckIn[]
): PsychologyCheckInSummary {
  return {
    checkInCount: checkIns.length,
    averageSleepHours: average(
      checkIns
        .map((row) => row.sleepHours)
        .filter((value): value is number => value != null)
    ),
    averageSleepQuality: average(
      checkIns
        .map((row) => row.sleepQuality)
        .filter((value): value is number => value != null)
    ),
    averageMorningRating: average(
      checkIns
        .map((row) => row.morningRating)
        .filter((value): value is number => value != null)
    ),
    averageStress: average(
      checkIns
        .map((row) => row.stressLevel)
        .filter((value): value is number => value != null)
    ),
    averageEnergy: average(
      checkIns
        .map((row) => row.energyLevel)
        .filter((value): value is number => value != null)
    ),
    averageFocus: average(
      checkIns
        .map((row) => row.focusLevel)
        .filter((value): value is number => value != null)
    ),
  }
}
