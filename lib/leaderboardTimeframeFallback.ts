import {
  buildLeaderboardChartData,
  type LeaderboardAccountTypeFilter,
  type LeaderboardChartRow,
  type LeaderboardCustomRange,
  type LeaderboardRankedTrader,
  type LeaderboardTodayStats,
  type LeaderboardView,
  type LeaderboardYourRank,
  type TradeForLeaderboard,
} from "./leaderboardChart.ts"

/** Smallest → largest preset windows (excludes Custom). */
export const LEADERBOARD_PRESET_VIEW_ORDER: readonly LeaderboardView[] = [
  "7D",
  "30D",
  "90D",
  "YTD",
  "ALL",
]

export type LeaderboardViewResolution = {
  requestedView: LeaderboardView
  effectiveView: LeaderboardView
  usedFallback: boolean
}

export type LeaderboardChartDataWithFallback = LeaderboardViewResolution & {
  chartData: LeaderboardChartRow[]
  todayStats: LeaderboardTodayStats
  rankedTraders: LeaderboardRankedTrader[]
  yourRank: LeaderboardYourRank | null
  hasData: boolean
}

/** Next larger preset after `view`, or null at ALL / unknown. Custom starts at 7D. */
export function nextLargerLeaderboardView(
  view: LeaderboardView
): LeaderboardView | null {
  if (view === "Custom") return "7D"
  const idx = LEADERBOARD_PRESET_VIEW_ORDER.indexOf(view)
  if (idx < 0 || idx >= LEADERBOARD_PRESET_VIEW_ORDER.length - 1) return null
  return LEADERBOARD_PRESET_VIEW_ORDER[idx + 1] ?? null
}

function chartHasEligibleData(
  trades: TradeForLeaderboard[],
  view: LeaderboardView,
  userId: string | null,
  customRange: LeaderboardCustomRange | undefined,
  accountTypeFilter: LeaderboardAccountTypeFilter
): boolean {
  return buildLeaderboardChartData(
    trades,
    view,
    userId,
    customRange,
    accountTypeFilter
  ).hasData
}

/**
 * Resolve the effective preset/custom view against one cached trade set.
 * Never performs network I/O — callers must not invoke on fetch failure.
 */
export function resolveLeaderboardEffectiveView(
  trades: TradeForLeaderboard[],
  requestedView: LeaderboardView,
  userId: string | null,
  customRange: LeaderboardCustomRange | undefined,
  accountTypeFilter: LeaderboardAccountTypeFilter
): LeaderboardViewResolution {
  if (requestedView === "Custom") {
    if (
      chartHasEligibleData(
        trades,
        "Custom",
        userId,
        customRange,
        accountTypeFilter
      )
    ) {
      return {
        requestedView,
        effectiveView: "Custom",
        usedFallback: false,
      }
    }
    let view: LeaderboardView | null = "7D"
    while (view) {
      if (
        chartHasEligibleData(trades, view, userId, undefined, accountTypeFilter)
      ) {
        return { requestedView, effectiveView: view, usedFallback: true }
      }
      view = nextLargerLeaderboardView(view)
    }
    return { requestedView, effectiveView: "Custom", usedFallback: false }
  }

  let view: LeaderboardView = requestedView
  while (true) {
    if (chartHasEligibleData(trades, view, userId, undefined, accountTypeFilter)) {
      return {
        requestedView,
        effectiveView: view,
        usedFallback: view !== requestedView,
      }
    }
    const next = nextLargerLeaderboardView(view)
    if (!next) {
      return { requestedView, effectiveView: requestedView, usedFallback: false }
    }
    view = next
  }
}

/** Build chart output once for the resolved effective view. */
export function buildLeaderboardChartDataWithFallback(
  trades: TradeForLeaderboard[],
  requestedView: LeaderboardView,
  userId: string | null,
  customRange: LeaderboardCustomRange | undefined,
  accountTypeFilter: LeaderboardAccountTypeFilter
): LeaderboardChartDataWithFallback {
  const resolution = resolveLeaderboardEffectiveView(
    trades,
    requestedView,
    userId,
    customRange,
    accountTypeFilter
  )
  const rangeForEffective =
    resolution.effectiveView === "Custom" ? customRange : undefined
  const built = buildLeaderboardChartData(
    trades,
    resolution.effectiveView,
    userId,
    rangeForEffective,
    accountTypeFilter
  )
  return { ...built, ...resolution }
}

export function leaderboardTimeframeFallbackMessage(
  requestedView: LeaderboardView,
  effectiveView: LeaderboardView
): string | null {
  if (requestedView === effectiveView) return null
  const requestedLabel = leaderboardViewLabel(requestedView)
  const effectiveLabel = leaderboardViewLabel(effectiveView)
  return `No results for ${requestedLabel} — showing ${effectiveLabel}`
}

function leaderboardViewLabel(view: LeaderboardView): string {
  switch (view) {
    case "7D":
      return "7 Days"
    case "30D":
      return "30 Days"
    case "90D":
      return "90 Days"
    case "YTD":
      return "Year to Date"
    case "ALL":
      return "All Time"
    case "Custom":
      return "Custom Range"
  }
}

/** Maps web presets to native timeframe ids for cross-platform test tables. */
export const LEADERBOARD_WEB_TO_NATIVE_TIMEFRAME: Record<
  Exclude<LeaderboardView, "Custom">,
  string
> = {
  "7D": "week",
  "30D": "month",
  "90D": "ninetyDays",
  YTD: "year",
  ALL: "allTime",
}
