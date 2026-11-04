"use client"

import { useEffect, useMemo, useState } from "react"
import { useDashboardAnalytics } from "@/app/(app)/dashboard/useDashboardAnalytics"
import type { DashboardAccountRow } from "@/app/components/dashboard/dashboardTypes"
import {
  buildDashboardScorecardFingerprint,
  readScorecardLastScope,
  readScorecardSession,
  scorecardScopeFiltersEqual,
  writeScorecardSession,
  type ScorecardScopeFilters,
} from "./scorecardSessionStore.ts"
import { resolveDashboardGearDefaults } from "@/lib/dashboardGearPrefs"
import { formatPsychologyDashboardScopeLabel } from "@/lib/psychology/psychologyScopeLabel"
import { excludeBacktestTrades } from "@/lib/tradeModeFilters"
import {
  isCopyGroupFilterValue,
  resolveCopyGroupAccountIdsForFilter,
  shouldFetchCopyTradingGroupsForFilter,
} from "@/lib/tradeAccountSelection"
import { useCachedAccounts, useCachedTrades, useTradesLoadError } from "@/lib/useAppDataCache"
import { useCopyTradingGroups } from "@/lib/useCopyTradingGroups"
import type { ScorecardAnalyticsContext, ScorecardResult } from "./types.ts"
import { useTradingScorecard } from "./useTradingScorecard.ts"

export type ScorecardPageStatus = "loading" | "error" | "empty" | "ready"

export type ScorecardPageHydration = {
  status: ScorecardPageStatus
  result: ScorecardResult | null
  scopeLabel: string
  errorMessage: string | null
  totalTradesInScope: number
  usingCachedSnapshot: boolean
}

function resolveScopeFilters(
  snapshot: ReturnType<typeof readScorecardSession>
): ScorecardScopeFilters {
  const lastScope = readScorecardLastScope()
  if (lastScope) return lastScope
  if (snapshot?.filters) return snapshot.filters
  const prefs = resolveDashboardGearDefaults()
  return {
    accountFilter: prefs.accountFilter,
    accountTypeFilter: prefs.accountTypeFilter,
    timeFilter: prefs.timeFilter,
    selectedDate: "",
    customRangeStart: "",
    customRangeEnd: "",
    showPublicOnly: prefs.showPublicOnly,
  }
}

export function useScorecardPageHydration(
  userId: string | null | undefined
): ScorecardPageHydration {
  const [snapshot] = useState(() => readScorecardSession())
  const scopeFilters = useMemo(() => resolveScopeFilters(snapshot), [snapshot])

  const { trades, loading: tradesLoading } = useCachedTrades(userId, {
    analyticsHistory: true,
  })
  const tradesLoadError = useTradesLoadError(userId)
  const { accounts: accountRows, loading: accountsLoading } = useCachedAccounts(userId)

  const [copyGroupsRequested, setCopyGroupsRequested] = useState(() =>
    isCopyGroupFilterValue(scopeFilters.accountFilter)
  )
  useEffect(() => {
    if (isCopyGroupFilterValue(scopeFilters.accountFilter)) {
      setCopyGroupsRequested(true)
    }
  }, [scopeFilters.accountFilter])

  const { copyGroups } = useCopyTradingGroups(
    userId,
    shouldFetchCopyTradingGroupsForFilter(copyGroupsRequested, scopeFilters.accountFilter)
  )

  const accountById = useMemo(() => {
    const m: Record<string, DashboardAccountRow> = {}
    accountRows.forEach((acc) => {
      m[String(acc.id)] = acc as DashboardAccountRow
    })
    return m
  }, [accountRows])

  const copyGroupAccountIds = useMemo(
    () => resolveCopyGroupAccountIdsForFilter(scopeFilters.accountFilter, copyGroups),
    [scopeFilters.accountFilter, copyGroups]
  )

  const tradesExcludingBacktest = useMemo(
    () => excludeBacktestTrades([...trades]),
    [trades]
  )

  const {
    filteredTrades,
    totalTrades,
    maxDrawdown,
    avgWin,
    avgLoss,
    periodTradingDayCount,
  } = useDashboardAnalytics({
    deferredTradesExcludingBacktest: tradesExcludingBacktest,
    showPublicOnly: scopeFilters.showPublicOnly,
    accountFilter: scopeFilters.accountFilter,
    accountTypeFilter: scopeFilters.accountTypeFilter,
    timeFilter: scopeFilters.timeFilter,
    selectedDate: scopeFilters.selectedDate,
    customRangeStart: scopeFilters.customRangeStart,
    customRangeEnd: scopeFilters.customRangeEnd,
    accountById,
    copyGroupAccountIds,
  })

  const scopeLabel = useMemo(
    () =>
      formatPsychologyDashboardScopeLabel({
        timeFilter: scopeFilters.timeFilter,
        selectedDate: scopeFilters.selectedDate,
        customRangeStart: scopeFilters.customRangeStart,
        customRangeEnd: scopeFilters.customRangeEnd,
        accountFilter: scopeFilters.accountFilter,
      }),
    [scopeFilters]
  )

  const scorecardAnalytics: ScorecardAnalyticsContext = useMemo(
    () => ({
      periodTradingDayCount,
      maxDrawdown,
      avgWin,
      avgLoss,
      totalTrades,
      postTripleLossWinRate: null,
    }),
    [periodTradingDayCount, maxDrawdown, avgWin, avgLoss, totalTrades]
  )

  const tradesReady =
    Boolean(userId) &&
    !tradesLoading &&
    (!accountsLoading || accountRows.length > 0)

  const dashboardRows = useMemo(
    () => filteredTrades as ReadonlyArray<Record<string, unknown>>,
    [filteredTrades]
  )

  const snapshotMatchesScope = useMemo(() => {
    if (!snapshot?.filters || !userId) return false
    return scorecardScopeFiltersEqual(snapshot.filters, scopeFilters)
  }, [snapshot, scopeFilters, userId])

  const { ready: scorecardReady, loadError: journalLoadError, result: liveResult } =
    useTradingScorecard({
      userId,
      dashboardTrades: dashboardRows,
      tradesReady,
      scopeLabel,
      analytics: scorecardAnalytics,
    })

  useEffect(() => {
    if (!userId || !liveResult) return
    writeScorecardSession({
      filterFingerprint: buildDashboardScorecardFingerprint({
        userId,
        accountFilter: scopeFilters.accountFilter,
        accountTypeFilter: scopeFilters.accountTypeFilter,
        timeFilter: scopeFilters.timeFilter,
        selectedDate: scopeFilters.selectedDate,
        customRangeStart: scopeFilters.customRangeStart,
        customRangeEnd: scopeFilters.customRangeEnd,
        showPublicOnly: scopeFilters.showPublicOnly,
        tradeCount: totalTrades,
      }),
      scopeLabel: liveResult.scopeLabel,
      result: liveResult,
      filters: scopeFilters,
    })
  }, [userId, liveResult, scopeFilters, totalTrades])

  const staleSnapshotResult =
    snapshotMatchesScope && snapshot?.result ? snapshot.result : null
  const result = liveResult ?? staleSnapshotResult
  const displayScope = result?.scopeLabel ?? snapshot?.scopeLabel ?? scopeLabel

  if (!userId) {
    return {
      status: "loading",
      result: null,
      scopeLabel: displayScope,
      errorMessage: null,
      totalTradesInScope: 0,
      usingCachedSnapshot: false,
    }
  }

  const fetchError = tradesLoadError ?? journalLoadError
  if (fetchError && !result) {
    return {
      status: "error",
      result: null,
      scopeLabel: displayScope,
      errorMessage: fetchError,
      totalTradesInScope: totalTrades,
      usingCachedSnapshot: false,
    }
  }

  const awaitingData =
    tradesLoading ||
    accountsLoading ||
    (!scorecardReady && !staleSnapshotResult)

  if (awaitingData) {
    return {
      status: "loading",
      result: staleSnapshotResult,
      scopeLabel: displayScope,
      errorMessage: null,
      totalTradesInScope: totalTrades,
      usingCachedSnapshot: Boolean(staleSnapshotResult && !liveResult),
    }
  }

  if (scorecardReady && totalTrades === 0) {
    return {
      status: "empty",
      result: null,
      scopeLabel: displayScope,
      errorMessage: null,
      totalTradesInScope: 0,
      usingCachedSnapshot: false,
    }
  }

  if (!result) {
    return {
      status: "empty",
      result: null,
      scopeLabel: displayScope,
      errorMessage: null,
      totalTradesInScope: totalTrades,
      usingCachedSnapshot: false,
    }
  }

  return {
    status: "ready",
    result,
    scopeLabel: displayScope,
    errorMessage: fetchError,
    totalTradesInScope: totalTrades,
    usingCachedSnapshot: Boolean(!liveResult && staleSnapshotResult),
  }
}
