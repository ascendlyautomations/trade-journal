"use client"

import { useRouter } from "next/navigation"
import { useCallback, useMemo } from "react"
import type { DashboardTradeRow } from "@/app/components/dashboard/dashboardTypes"
import {
  buildDashboardScorecardFingerprint,
  writeScorecardSession,
  type ScorecardScopeFilters,
} from "@/lib/scorecard/scorecardSessionStore"
import { useTradingScorecard } from "@/lib/scorecard/useTradingScorecard"
import type { ScorecardAnalyticsContext } from "@/lib/scorecard/types"
import TradingScorecardDashboardSection from "./TradingScorecardDashboardSection"

export type DashboardTradingScorecardProps = {
  userId: string
  filteredTrades: DashboardTradeRow[]
  tradesReady: boolean
  scopeLabel: string
  proFeatureUnlocked: boolean
  analytics: ScorecardAnalyticsContext
  filterFingerprint: string
  scopeFilters: ScorecardScopeFilters
}

export default function DashboardTradingScorecard({
  userId,
  filteredTrades,
  tradesReady,
  scopeLabel,
  proFeatureUnlocked,
  analytics,
  filterFingerprint,
  scopeFilters,
}: DashboardTradingScorecardProps) {
  const router = useRouter()
  const dashboardRows = useMemo(
    () => filteredTrades as ReadonlyArray<Record<string, unknown>>,
    [filteredTrades]
  )

  const { ready, result, highlights } = useTradingScorecard({
    userId,
    dashboardTrades: dashboardRows,
    tradesReady,
    scopeLabel,
    analytics,
  })

  const onOpenDetail = useCallback(() => {
    if (!result) {
      router.push("/scorecard")
      return
    }
    writeScorecardSession({
      filterFingerprint,
      scopeLabel: result.scopeLabel,
      result,
      filters: scopeFilters,
    })
    router.push("/scorecard")
  }, [filterFingerprint, result, router, scopeFilters])

  return (
    <TradingScorecardDashboardSection
      result={result}
      ready={ready}
      highlights={highlights}
      onOpenDetail={onOpenDetail}
      proFeatureUnlocked={proFeatureUnlocked}
    />
  )
}

export { buildDashboardScorecardFingerprint } from "@/lib/scorecard/scorecardSessionStore"
