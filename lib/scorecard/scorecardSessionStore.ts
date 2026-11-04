import type { ScorecardResult } from "./types.ts"

const STORAGE_KEY = "tt.scorecard.session.v1"
const LAST_SCOPE_KEY = "tt.scorecard.lastScope.v1"

/** Dashboard filter state used to recompute the scorecard without a full refetch. */
export type ScorecardScopeFilters = {
  accountFilter: string
  accountTypeFilter: string
  timeFilter: string
  selectedDate: string
  customRangeStart: string
  customRangeEnd: string
  showPublicOnly: boolean
}

export type ScorecardSessionSnapshot = {
  filterFingerprint: string
  scopeLabel: string
  result: ScorecardResult
  filters?: ScorecardScopeFilters
}

export function writeScorecardSession(snapshot: ScorecardSessionSnapshot): void {
  if (typeof sessionStorage === "undefined") return
  try {
    sessionStorage.setItem(STORAGE_KEY, JSON.stringify(snapshot))
  } catch {
    // ignore quota
  }
}

export function readScorecardSession(): ScorecardSessionSnapshot | null {
  if (typeof sessionStorage === "undefined") return null
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY)
    if (!raw) return null
    return JSON.parse(raw) as ScorecardSessionSnapshot
  } catch {
    return null
  }
}

export function writeScorecardLastScope(filters: ScorecardScopeFilters): void {
  if (typeof sessionStorage === "undefined") return
  try {
    sessionStorage.setItem(LAST_SCOPE_KEY, JSON.stringify(filters))
  } catch {
    // ignore quota
  }
}

export function readScorecardLastScope(): ScorecardScopeFilters | null {
  if (typeof sessionStorage === "undefined") return null
  try {
    const raw = sessionStorage.getItem(LAST_SCOPE_KEY)
    if (!raw) return null
    return JSON.parse(raw) as ScorecardScopeFilters
  } catch {
    return null
  }
}

export function scorecardScopeFiltersEqual(
  a: ScorecardScopeFilters,
  b: ScorecardScopeFilters
): boolean {
  return (
    a.accountFilter === b.accountFilter &&
    a.accountTypeFilter === b.accountTypeFilter &&
    a.timeFilter === b.timeFilter &&
    a.selectedDate === b.selectedDate &&
    a.customRangeStart === b.customRangeStart &&
    a.customRangeEnd === b.customRangeEnd &&
    a.showPublicOnly === b.showPublicOnly
  )
}

/** Scope identity without trade count — used to reject stale snapshots. */
export function scorecardScopeKey(parts: {
  userId: string
  accountFilter: string
  accountTypeFilter: string
  timeFilter: string
  selectedDate: string
  customRangeStart: string
  customRangeEnd: string
  showPublicOnly: boolean
}): string {
  return [
    parts.userId,
    parts.accountFilter,
    parts.accountTypeFilter,
    parts.timeFilter,
    parts.selectedDate,
    parts.customRangeStart,
    parts.customRangeEnd,
    parts.showPublicOnly ? "1" : "0",
  ].join("|")
}

export function scorecardFilterFingerprint(parts: {
  userId: string
  accountFilter: string
  accountTypeFilter: string
  timeFilter: string
  selectedDate: string
  customRangeStart: string
  customRangeEnd: string
  showPublicOnly: boolean
  tradeCount: number
}): string {
  return `${scorecardScopeKey(parts)}|${String(parts.tradeCount)}`
}

export function buildDashboardScorecardFingerprint(
  input: Parameters<typeof scorecardFilterFingerprint>[0]
): string {
  return scorecardFilterFingerprint(input)
}
