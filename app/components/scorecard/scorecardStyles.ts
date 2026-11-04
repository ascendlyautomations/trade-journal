export const scorecardPanelClass =
  "rounded-xl border border-white/10 bg-white/5 p-4 md:p-5 dark:border-white/10 dark:bg-white/5"

export const scorecardTitleClass = "text-sm font-semibold text-white"

export const scorecardSubtitleClass = "text-xs text-gray-400"

export const scorecardMetricClass = "text-2xl font-bold tabular-nums text-white md:text-3xl"

export const scorecardBarTrackClass = "h-2 w-full overflow-hidden rounded-full bg-white/10"

export function scorecardBarFillClass(score: number | null): string {
  if (score == null) return "h-full w-0 bg-gray-600"
  if (score >= 70) return "h-full rounded-full bg-emerald-500/90 transition-all"
  if (score >= 45) return "h-full rounded-full bg-amber-500/90 transition-all"
  return "h-full rounded-full bg-rose-500/80 transition-all"
}
