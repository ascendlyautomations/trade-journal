import { isDemoUserId } from "@/lib/demo/constants"
import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "@/lib/dailyCheckIn/dateKey"
import { fetchPsychologyDashboardCheckIns } from "@/lib/dailyCheckIn/repository"
import { readRecentCheckInsCache, writeRecentCheckInsCache } from "@/lib/dailyCheckIn/sessionCache"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types"
import { supabase } from "@/lib/supabaseClient"
import { buildPsychologyAnalyticsReport } from "./reports/engine.ts"
import { buildPsychologyCoachDeterministicSummary } from "./reports/coach.ts"
import { buildPsychologyCoachFacts } from "./reports/facts.ts"
import { ensurePsychologyJournalTrades } from "./reports/journalTrades.ts"
import type { PsychologyReportTrade } from "./reports/types.ts"
import type { PsychologyCoachSummary } from "./reports/coach.ts"
import {
  createPsychologyAnalyticsScope,
  type PsychologyAnalyticsScope,
} from "./psychologyScope.ts"
import {
  getPsychologyAnalyticsScope,
  getPsychologySession,
  setPsychologyAnalyticsScope,
  setPsychologySession,
} from "./psychologySessionStore.ts"
import type { PsychologyAnalyticsReport, PsychologyCoachFacts } from "./reports/types.ts"

export type PsychologySessionSnapshot = {
  report: PsychologyAnalyticsReport | null
  facts: PsychologyCoachFacts | null
  summary: PsychologyCoachSummary | null
  checkIns: TraderDailyCheckIn[]
  journalTrades: PsychologyReportTrade[]
  scope: PsychologyAnalyticsScope | null
}

export type HydratePsychologySessionOptions = {
  scopeLabel?: string
  /** When true, rebuild even if the trade-scope fingerprint is unchanged. */
  forceRebuild?: boolean
}

export async function loadPsychologyJournalInputs(
  userId: string,
  dashboardTrades: ReadonlyArray<Record<string, unknown>> = []
): Promise<{ checkIns: TraderDailyCheckIn[]; journalTrades: PsychologyReportTrade[] }> {
  const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
  const end = todayCheckInDateKey()
  const cached = readRecentCheckInsCache(userId, start, end)
  const [journalTrades, checkIns] = await Promise.all([
    ensurePsychologyJournalTrades(userId, dashboardTrades),
    cached !== undefined
      ? Promise.resolve(cached)
      : fetchPsychologyDashboardCheckIns(supabase, userId),
  ])
  if (cached === undefined) {
    writeRecentCheckInsCache(userId, start, end, checkIns)
  }
  return { checkIns, journalTrades }
}

function resolveHydrationScope(
  userId: string,
  dashboardTrades: ReadonlyArray<Record<string, unknown>>,
  scopeLabel?: string
): PsychologyAnalyticsScope {
  const stored = getPsychologyAnalyticsScope()
  const label =
    scopeLabel ??
    stored?.label ??
    "Recent journal trades (dashboard filters apply when opened from Dashboard)"
  return createPsychologyAnalyticsScope(userId, label, dashboardTrades)
}

/** Rebuild analytics session from authorized journal trades + check-ins. */
export async function hydratePsychologySession(
  userId: string,
  dashboardTrades: ReadonlyArray<Record<string, unknown>> = [],
  options: HydratePsychologySessionOptions = {}
): Promise<PsychologySessionSnapshot> {
  if (isDemoUserId(userId)) {
    setPsychologySession({
      report: null,
      facts: null,
      summary: null,
      userId,
      scopeFingerprint: null,
      scopeLabel: null,
    })
    setPsychologyAnalyticsScope(null)
    return {
      report: null,
      facts: null,
      summary: null,
      checkIns: [],
      journalTrades: [],
      scope: null,
    }
  }

  const scope = resolveHydrationScope(userId, dashboardTrades, options.scopeLabel)
  setPsychologyAnalyticsScope(scope)

  const current = getPsychologySession()
  const scopeUnchanged =
    current.report &&
    current.facts &&
    current.userId === userId &&
    current.scopeFingerprint === scope.fingerprint

  const { checkIns, journalTrades } = await loadPsychologyJournalInputs(
    userId,
    dashboardTrades
  )

  if (scopeUnchanged && !options.forceRebuild) {
    return {
      report: current.report,
      facts: current.facts,
      summary: current.summary,
      checkIns,
      journalTrades,
      scope,
    }
  }

  const report = buildPsychologyAnalyticsReport(journalTrades, checkIns)
  const facts = buildPsychologyCoachFacts(report, journalTrades, checkIns)
  const summary = buildPsychologyCoachDeterministicSummary(facts)
  setPsychologySession({
    report,
    facts,
    summary,
    userId,
    scopeFingerprint: scope.fingerprint,
    scopeLabel: scope.label,
  })

  return {
    report,
    facts,
    summary,
    checkIns,
    journalTrades,
    scope,
  }
}

/**
 * Analytics route hydration — uses dashboard scope when set, otherwise recent journal trades.
 * Always rebuilds the report for the resolved trade set (no stale report reuse).
 */
export async function hydratePsychologySessionForAnalytics(
  userId: string,
  dashboardTrades?: ReadonlyArray<Record<string, unknown>>
): Promise<PsychologySessionSnapshot> {
  const scope = getPsychologyAnalyticsScope()
  const trades = dashboardTrades ?? scope?.trades ?? []
  const label = scope?.label
  return hydratePsychologySession(userId, trades, {
    scopeLabel: label,
    forceRebuild: true,
  })
}

/** @deprecated Prefer hydratePsychologySessionForAnalytics — never reuses report across scopes. */
export async function hydratePsychologySessionIfEmpty(
  userId: string,
  dashboardTrades: ReadonlyArray<Record<string, unknown>> = []
): Promise<PsychologySessionSnapshot> {
  return hydratePsychologySessionForAnalytics(userId, dashboardTrades)
}
