import { isDemoUserId } from "@/lib/demo/constants"
import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "@/lib/dailyCheckIn/dateKey"
import { fetchCheckInsInRange } from "@/lib/dailyCheckIn/repository"
import { readRecentCheckInsCache, writeRecentCheckInsCache } from "@/lib/dailyCheckIn/sessionCache"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types"
import { supabase } from "@/lib/supabaseClient"
import { buildPsychologyAnalyticsReport } from "./reports/engine.ts"
import { buildPsychologyCoachDeterministicSummary } from "./reports/coach.ts"
import { buildPsychologyCoachFacts } from "./reports/facts.ts"
import { ensurePsychologyJournalTrades } from "./reports/journalTrades.ts"
import type { PsychologyReportTrade } from "./reports/types.ts"
import type { PsychologyCoachSummary } from "./reports/coach.ts"
import { getPsychologySession, setPsychologySession } from "./psychologySessionStore.ts"
import type { PsychologyAnalyticsReport, PsychologyCoachFacts } from "./reports/types.ts"

export type PsychologySessionSnapshot = {
  report: PsychologyAnalyticsReport | null
  facts: PsychologyCoachFacts | null
  summary: PsychologyCoachSummary | null
  checkIns: TraderDailyCheckIn[]
  journalTrades: PsychologyReportTrade[]
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
    cached
      ? Promise.resolve(cached)
      : fetchCheckInsInRange(supabase, userId, start, end),
  ])
  if (!cached) {
    writeRecentCheckInsCache(userId, start, end, checkIns)
  }
  return { checkIns, journalTrades }
}

/** Rebuild analytics session from authorized journal trades + check-ins. */
export async function hydratePsychologySession(
  userId: string,
  dashboardTrades: ReadonlyArray<Record<string, unknown>> = []
): Promise<PsychologySessionSnapshot> {
  if (isDemoUserId(userId)) {
    setPsychologySession({ report: null, facts: null, summary: null })
    return {
      report: null,
      facts: null,
      summary: null,
      checkIns: [],
      journalTrades: [],
    }
  }

  const { checkIns, journalTrades } = await loadPsychologyJournalInputs(
    userId,
    dashboardTrades
  )
  const report = buildPsychologyAnalyticsReport(journalTrades, checkIns)
  const facts = buildPsychologyCoachFacts(report, journalTrades, checkIns)
  const summary = buildPsychologyCoachDeterministicSummary(facts)
  setPsychologySession({ report, facts, summary })

  return {
    report,
    facts,
    summary,
    checkIns,
    journalTrades,
  }
}

export async function hydratePsychologySessionIfEmpty(
  userId: string,
  dashboardTrades: ReadonlyArray<Record<string, unknown>> = []
): Promise<PsychologySessionSnapshot> {
  const current = getPsychologySession()
  if (current.report && current.facts) {
    const { checkIns, journalTrades } = await loadPsychologyJournalInputs(
      userId,
      dashboardTrades
    )
    return {
      report: current.report,
      facts: current.facts,
      summary: current.summary,
      checkIns,
      journalTrades,
    }
  }
  return hydratePsychologySession(userId, dashboardTrades)
}
