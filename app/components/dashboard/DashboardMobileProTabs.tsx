"use client"

import type { ComponentProps, ReactNode } from "react"
import { DashboardPsychologyInsightsSlot } from "./DashboardPsychologyInsights"
import DashboardInsights from "./DashboardInsights"
import MobileWebDashboardChartBlock, {
  MobileWebDashboardSectionHeader,
} from "@/app/components/mobile/dashboard/MobileWebDashboardChartBlock"
import MobileWebDashboardHoldTime from "@/app/components/mobile/dashboard/MobileWebDashboardHoldTime"
import MobileWebDashboardHourTimeline from "@/app/components/mobile/dashboard/MobileWebDashboardHourTimeline"
import MobileWebDashboardInsights from "@/app/components/mobile/dashboard/MobileWebDashboardInsights"
import MobileWebDashboardLongShort from "@/app/components/mobile/dashboard/MobileWebDashboardLongShort"
import MobileWebDashboardPerformanceGrid from "@/app/components/mobile/dashboard/MobileWebDashboardPerformanceGrid"
import MobileWebDashboardRrTarget from "@/app/components/mobile/dashboard/MobileWebDashboardRrTarget"
import MobileWebDashboardSymbols from "@/app/components/mobile/dashboard/MobileWebDashboardSymbols"
import MobileWebDashboardWinLoss from "@/app/components/mobile/dashboard/MobileWebDashboardWinLoss"
import {
  buildMobileWebDashboardPerformanceCards,
  mobileWebDashboardHourBars,
  mobileWebDashboardHourBarsHaveSignal,
} from "@/lib/mobileWebDashboard"
import type { DashboardRrTargetAnalysis } from "@/lib/dashboardRrTargetAnalysis"
import type { HoldTimeStats } from "@/lib/dashboardHoldTimeStats"
import type { LongShortPerformance } from "@/lib/dashboardLongShortStats"

type HourData = {
  hourlyMap: Record<number, number>
  hasValidTradingHoursData: boolean
  bestHour: number | null
  worstHour: number | null
} | null

type DashboardMobileProTabsProps = {
  deferredSectionsReady: boolean
  weekdaySlot: ReactNode
  sessionsSlot: ReactNode
  showSessions: boolean
  hourData: HourData
  maxDrawdown: number
  avgWin: number
  avgLoss: number
  bestTrade: number
  biggestLoss: number
  payoutsTotal?: number | null
  winRate: number
  winCount: number
  lossCount: number
  rrTargetAnalysis: DashboardRrTargetAnalysis
  symbolPerformanceRows: Array<{
    ticker: string
    totalTrades: number
    wins: number
    winRate: number
    totalPnL: number
    avgRR: number | null
  }>
  hasAnyTrades: boolean
  longShortPerformance: LongShortPerformance
  holdTimeStats: HoldTimeStats
  totalTrades: number
  insightsProps: ComponentProps<typeof DashboardInsights>
}

/**
 * Phone-only Pro dashboard body. Mirrors native DashboardHomeView:
 * Performance cards → Win/Loss → Behavior charts → Execution → Insights.
 * Desktop must not render this.
 */
export default function DashboardMobileProTabs({
  deferredSectionsReady,
  weekdaySlot,
  sessionsSlot,
  showSessions,
  hourData,
  maxDrawdown,
  avgWin,
  avgLoss,
  bestTrade,
  biggestLoss,
  payoutsTotal = null,
  winRate,
  winCount,
  lossCount,
  rrTargetAnalysis,
  symbolPerformanceRows,
  longShortPerformance,
  holdTimeStats,
  totalTrades,
  insightsProps,
}: DashboardMobileProTabsProps) {
  const performanceCards = buildMobileWebDashboardPerformanceCards({
    avgWin,
    avgLoss,
    bestTrade,
    biggestLoss,
    maxDrawdown,
    payoutsTotal,
  })
  const hourBars = mobileWebDashboardHourBars(hourData?.hourlyMap)
  const showHourTimeline =
    Boolean(hourData?.hasValidTradingHoursData) &&
    mobileWebDashboardHourBarsHaveSignal(hourBars)

  return (
    <div
      className="flex flex-col gap-5 md:hidden"
      data-testid="dashboard-mobile-one-scroll"
    >
      <div className="flex flex-col gap-3">
        <MobileWebDashboardSectionHeader
          title="Performance"
          subtitle="Outcome quality for this period"
        />
        <MobileWebDashboardPerformanceGrid cards={performanceCards} />
      </div>

      <MobileWebDashboardChartBlock
        title="Win / Loss"
        subtitle="Wins versus losses in this period"
      >
        <MobileWebDashboardWinLoss
          winRate={winRate}
          winCount={winCount}
          lossCount={lossCount}
        />
      </MobileWebDashboardChartBlock>

      <MobileWebDashboardSectionHeader title="Behavior" />

      {showSessions ? (
        <MobileWebDashboardChartBlock
          title="Trading Sessions"
          subtitle="Where your trades clustered this period"
        >
          {sessionsSlot}
        </MobileWebDashboardChartBlock>
      ) : null}

      <MobileWebDashboardChartBlock
        title="Weekdays"
        subtitle="P&L across the trading week"
      >
        {weekdaySlot}
      </MobileWebDashboardChartBlock>

      <MobileWebDashboardChartBlock
        title="Long vs Short"
        subtitle="Direction mix for this period"
      >
        {deferredSectionsReady ? (
          <MobileWebDashboardLongShort
            performance={longShortPerformance}
            totalTrades={totalTrades}
          />
        ) : (
          <div className="h-44 animate-pulse rounded-[10px] bg-[color:var(--tt-surface-nested,#1a222c)]" />
        )}
      </MobileWebDashboardChartBlock>

      {showHourTimeline ? (
        <MobileWebDashboardChartBlock
          title="Trading Hours"
          subtitle="Hourly P&L across the session day"
        >
          <MobileWebDashboardHourTimeline
            hourlyMap={hourData?.hourlyMap ?? {}}
            bestHour={hourData?.bestHour ?? null}
            worstHour={hourData?.worstHour ?? null}
          />
        </MobileWebDashboardChartBlock>
      ) : null}

      <MobileWebDashboardChartBlock
        title="R:R Targeting"
        subtitle="Target R:R vs how far trades ran before exit"
      >
        <MobileWebDashboardRrTarget analysis={rrTargetAnalysis} />
      </MobileWebDashboardChartBlock>

      {symbolPerformanceRows.length > 0 ? (
        <MobileWebDashboardChartBlock
          title="Symbol Performance"
          subtitle="Strongest and weakest instruments in this period"
        >
          <MobileWebDashboardSymbols rows={symbolPerformanceRows} />
        </MobileWebDashboardChartBlock>
      ) : null}

      <MobileWebDashboardSectionHeader title="Execution" />

      <MobileWebDashboardChartBlock title="Hold Time">
        {deferredSectionsReady ? (
          <MobileWebDashboardHoldTime
            stats={holdTimeStats}
            totalTrades={totalTrades}
          />
        ) : (
          <div className="h-44 animate-pulse rounded-[10px] bg-[color:var(--tt-surface-nested,#1a222c)]" />
        )}
      </MobileWebDashboardChartBlock>

      <MobileWebDashboardInsights {...insightsProps} />
      <DashboardPsychologyInsightsSlot slot="mobile" />
    </div>
  )
}
