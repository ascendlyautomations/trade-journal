"use client"

import { useMemo } from "react"
import { usePsychologyJournalInputs } from "../psychology/usePsychologyJournalInputs.ts"
import { buildTradingScorecard, collectTopStrengthsAndWeaknesses } from "./buildScorecard.ts"
import { mergeScorecardTrades } from "./tradeMapping.ts"
import type { ScorecardAnalyticsContext, ScorecardResult } from "./types.ts"

export type UseTradingScorecardParams = {
  userId: string | null | undefined
  /** Filtered dashboard rows in current scope */
  dashboardTrades: ReadonlyArray<Record<string, unknown>>
  tradesReady: boolean
  scopeLabel: string
  analytics: ScorecardAnalyticsContext
}

export type UseTradingScorecardResult = {
  ready: boolean
  loadError: string | null
  result: ScorecardResult | null
  highlights: ReturnType<typeof collectTopStrengthsAndWeaknesses>
}

export function useTradingScorecard({
  userId,
  dashboardTrades,
  tradesReady,
  scopeLabel,
  analytics,
}: UseTradingScorecardParams): UseTradingScorecardResult {
  const { checkIns, trades: journalTrades, ready: journalReady, loadError } =
    usePsychologyJournalInputs(userId, dashboardTrades)

  const scopedIds = useMemo(
    () => new Set(dashboardTrades.map((r) => String(r.id ?? "").trim()).filter(Boolean)),
    [dashboardTrades]
  )

  const journalInScope = useMemo(
    () => journalTrades.filter((t) => scopedIds.has(t.id)),
    [journalTrades, scopedIds]
  )

  const ready = tradesReady && journalReady && dashboardTrades.length >= 0

  const result = useMemo(() => {
    if (!ready) return null
    if (analytics.totalTrades === 0) return null
    const merged = mergeScorecardTrades(dashboardTrades, journalInScope)
    if (merged.length === 0) return null
    return buildTradingScorecard({
      scopeLabel,
      trades: merged,
      checkIns,
      analytics,
    })
  }, [
    ready,
    dashboardTrades,
    journalInScope,
    checkIns,
    scopeLabel,
    analytics,
  ])

  const highlights = useMemo(
    () => (result ? collectTopStrengthsAndWeaknesses(result) : { strengths: [], weaknesses: [] }),
    [result]
  )

  return { ready, loadError, result, highlights }
}
