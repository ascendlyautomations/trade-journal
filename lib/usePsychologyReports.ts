"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { isDemoUserId } from "@/lib/demo/constants"
import {
  CHECK_IN_HISTORY_DAY_WINDOW,
  checkInHistoryStartDateKey,
  todayCheckInDateKey,
} from "@/lib/dailyCheckIn/dateKey"
import { fetchPsychologyDashboardCheckIns } from "@/lib/dailyCheckIn/repository"
import { waitForDailyCheckInAuthSession } from "@/lib/dailyCheckIn/authSession"
import {
  readRecentCheckInsCache,
  writeRecentCheckInsCache,
} from "@/lib/dailyCheckIn/sessionCache"
import { supabase } from "@/lib/supabaseClient"
import { toUserFacingErrorMessage } from "@/lib/userFacingError"
import {
  PSYCHOLOGY_REPORT_CATALOG,
  isPeriodicPsychologyTemplate,
  psychologyReportSubtitle,
} from "@/lib/psychology/reports/catalog"
import { generatePsychologyReport } from "@/lib/psychology/reports/generator"
import {
  ensurePsychologyJournalTrades,
  journalTradeFingerprint,
} from "@/lib/psychology/reports/journalTrades"
import {
  availablePsychologyCatalog,
  catalogCardPeriods,
  defaultPeriodForTemplate,
  psychologyPeriodBounds,
  reportIDForRef,
} from "@/lib/psychology/reports/periods"
import type {
  PsychologyReport,
  PsychologyReportPeriodRef,
  PsychologyReportTemplate,
  PsychologyReportTrade,
} from "@/lib/psychology/reports/types"
import type { TraderDailyCheckIn } from "@/lib/dailyCheckIn/types"

export type PsychologyReportCard = {
  template: PsychologyReportTemplate
  title: string
  subtitle: string
  periodRef: PsychologyReportPeriodRef
  availablePeriods: PsychologyReportPeriodRef[]
}

type PsychologyReportsState = {
  trades: PsychologyReportTrade[]
  checkIns: TraderDailyCheckIn[]
  catalog: PsychologyReportPeriodRef[]
}

const reportCache = new Map<string, PsychologyReport>()

export function usePsychologyReports(
  userId: string | null | undefined,
  dashboardTrades: ReadonlyArray<Record<string, unknown>>,
  enabled: boolean
) {
  const [ready, setReady] = useState(false)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [inputs, setInputs] = useState<PsychologyReportsState | null>(null)
  const tradesFingerprint = useMemo(
    () => journalTradeFingerprint(dashboardTrades),
    [dashboardTrades]
  )

  const load = useCallback(async () => {
    if (!userId || !enabled) return
    if (isDemoUserId(userId)) {
      setInputs({ trades: [], checkIns: [], catalog: availablePsychologyCatalog([]) })
      setReady(true)
      return
    }
    setLoading(true)
    try {
      const authReady = await waitForDailyCheckInAuthSession(supabase)
      if (!authReady) {
        setLoadError("Sign in to load daily check-ins.")
        setReady(true)
        return
      }
      const start = checkInHistoryStartDateKey(CHECK_IN_HISTORY_DAY_WINDOW)
      const end = todayCheckInDateKey()
      const cachedCheckIns = readRecentCheckInsCache(userId, start, end)
      const [trades, checkIns] = await Promise.all([
        ensurePsychologyJournalTrades(userId, dashboardTrades),
        cachedCheckIns !== undefined
          ? Promise.resolve(cachedCheckIns)
          : fetchPsychologyDashboardCheckIns(supabase, userId),
      ])
      if (cachedCheckIns === undefined) {
        writeRecentCheckInsCache(userId, start, end, checkIns)
      }
      reportCache.clear()
      setInputs({
        trades,
        checkIns,
        catalog: availablePsychologyCatalog(trades),
      })
      setLoadError(null)
      setReady(true)
    } catch (error) {
      setLoadError(toUserFacingErrorMessage(error))
      setReady(true)
    } finally {
      setLoading(false)
    }
  }, [dashboardTrades, enabled, tradesFingerprint, userId])

  useEffect(() => {
    if (!enabled || !userId) return
    void load()
  }, [enabled, load, userId])

  const cards = useMemo<PsychologyReportCard[]>(() => {
    const catalog = inputs?.catalog ?? availablePsychologyCatalog([])
    return PSYCHOLOGY_REPORT_CATALOG.map((row) => {
      const periods = catalogCardPeriods(catalog, row.template)
      const periodRef = defaultPeriodForTemplate(catalog, row.template)
      const bounds = psychologyPeriodBounds(periodRef)
      return {
        template: row.template,
        title: row.title,
        subtitle: isPeriodicPsychologyTemplate(row.template)
          ? bounds.dateRangeLabel
          : psychologyReportSubtitle(row.template),
        periodRef,
        availablePeriods: periods.length ? periods : [periodRef],
      }
    })
  }, [inputs?.catalog])

  const getReport = useCallback(
    (ref: PsychologyReportPeriodRef): PsychologyReport | null => {
      if (!inputs) return null
      const id = reportIDForRef(ref)
      const cached = reportCache.get(id)
      if (cached) return cached
      const report = generatePsychologyReport(ref, inputs.trades, inputs.checkIns)
      reportCache.set(id, report)
      return report
    },
    [inputs]
  )

  return {
    ready,
    loading,
    loadError,
    cards,
    catalog: inputs?.catalog ?? [],
    refresh: load,
    getReport,
  }
}
