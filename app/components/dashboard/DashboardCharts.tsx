"use client"

import dynamic from "next/dynamic"
import { memo, type ComponentProps, type ReactNode } from "react"
import DashboardMobileProTabs from "./DashboardMobileProTabs"
import DashboardStatsGrid from "./DashboardStatsGrid"
import type { WeekdayChartPoint } from "./DashboardWeekdayChart"
import MobileWebDashboardSessions from "@/app/components/mobile/dashboard/MobileWebDashboardSessions"
import MobileWebDashboardWeekdays from "@/app/components/mobile/dashboard/MobileWebDashboardWeekdays"
import { lastEquityPointValue } from "@/lib/mobileWebDashboard"
import type { DashboardRrTargetAnalysis } from "@/lib/dashboardRrTargetAnalysis"

const EMPTY_RR_TARGET: DashboardRrTargetAnalysis = {
  tradeCount: 0,
  pairedCount: 0,
  pairedNonPositiveCount: 0,
  pairedPositiveCount: 0,
  avgTargetRr: null,
  avgMaxRrReached: null,
  avgTargetAttainmentRatio: null,
  sampleSummary: null,
  headline: null,
  bullets: [],
}

const DashboardEquityCurve = dynamic(() => import("./DashboardEquityCurve"), {
  loading: () => (
    <div className="h-[256px] animate-pulse bg-white/5 md:h-[300px] md:rounded-xl md:border md:border-white/10" />
  ),
})
const DashboardSessionChart = dynamic(() => import("./DashboardSessionChart"), {
  loading: () => <div className="h-48 animate-pulse rounded-lg bg-white/5" />,
})
const DashboardMaxDrawdown = dynamic(() => import("./DashboardMaxDrawdown"), {
  loading: () => <div className="h-24 animate-pulse rounded-xl bg-white/5" />,
})

type MobileProTabsProps = Omit<
  ComponentProps<typeof DashboardMobileProTabs>,
  | "weekdaySlot"
  | "sessionsSlot"
  | "hourData"
  | "showSessions"
  | "avgWin"
  | "bestTrade"
  | "avgLoss"
  | "biggestLoss"
  | "maxDrawdown"
  | "winRate"
  | "winCount"
  | "lossCount"
  | "rrTargetAnalysis"
  | "payoutsTotal"
  | "totalTrades"
  | "deferredSectionsReady"
>

type DashboardChartsProps = Omit<
  ComponentProps<typeof DashboardStatsGrid>,
  | "isPro"
  | "mobileEquitySlot"
  | "mobileWeekdayPnlSlot"
  | "mobileSessionsSlot"
  | "maxDrawdownSlot"
> & {
  isPro: boolean
  deferredSectionsReady: boolean
  equityData: ComponentProps<typeof DashboardEquityCurve>["data"]
  weekdayData: WeekdayChartPoint[]
  sessionPieData: ComponentProps<typeof DashboardSessionChart>["sessionPieData"]
  sessionBuckets: ComponentProps<typeof DashboardSessionChart>["sessionBuckets"]
  maxDrawdown: ComponentProps<typeof DashboardMaxDrawdown>["maxDrawdown"]
  showDrawdown: boolean
  currentStreak: number
  avgDay: number
  consistency: number
  recentTrades: ReactNode
  /** When set, Pro phone renders the native-style one-scroll dashboard. */
  mobileProTabs?: MobileProTabsProps
  liveAccountValue?: ReactNode
  drawdownLimitLineY?: number | null
  equityCurveUsesAccountBalance?: boolean
  showPersonalDrawdownFloor?: boolean
  timeframeLabel?: string
  winCount?: number
  lossCount?: number
  rrTargetAnalysis?: DashboardRrTargetAnalysis
  payoutsTotal?: number | null
}

function ChartSkeleton({ className }: { className: string }) {
  return (
    <div
      className={`${className} animate-pulse rounded-xl border border-white/10 bg-white/5`}
    />
  )
}

function DashboardCharts({
  isPro,
  deferredSectionsReady,
  equityData,
  weekdayData,
  sessionPieData,
  sessionBuckets,
  maxDrawdown,
  showDrawdown,
  currentStreak,
  avgDay,
  consistency,
  recentTrades,
  totalTrades,
  winRate,
  avgRR,
  avgMaxRrReached = null,
  totalPnL,
  profitFactor,
  avgWin,
  bestTrade,
  avgLoss,
  biggestLoss,
  bestDay,
  worstDay,
  periodTradingDayCount,
  showEquity,
  expectancyData,
  streakData,
  hourData,
  showSessions,
  bestWinStreak,
  mobileProTabs,
  liveAccountValue = null,
  drawdownLimitLineY = null,
  equityCurveUsesAccountBalance = false,
  showPersonalDrawdownFloor = false,
  timeframeLabel = "",
  winCount = 0,
  lossCount = 0,
  rrTargetAnalysis,
  payoutsTotal = null,
}: DashboardChartsProps) {
  const weekdayChart = deferredSectionsReady ? (
    <MobileWebDashboardWeekdays data={weekdayData} totalTrades={totalTrades} />
  ) : (
    <ChartSkeleton className="h-48" />
  )

  const sessionChartDesktop = deferredSectionsReady ? (
    <DashboardSessionChart
      variant="desktop"
      sessionPieData={sessionPieData}
      sessionBuckets={sessionBuckets}
      totalTrades={totalTrades}
    />
  ) : (
    <ChartSkeleton className="h-48" />
  )

  const sessionChartMobile = deferredSectionsReady ? (
    <MobileWebDashboardSessions
      sessionBuckets={sessionBuckets}
      totalTrades={totalTrades}
    />
  ) : (
    <ChartSkeleton className="h-48" />
  )

  const mobileEquity = deferredSectionsReady ? (
    <DashboardEquityCurve
      variant="mobile"
      data={equityData}
      totalTrades={totalTrades}
      drawdownLimitLineY={drawdownLimitLineY}
      equityCurveUsesAccountBalance={equityCurveUsesAccountBalance}
      showPersonalDrawdownFloor={showPersonalDrawdownFloor}
    />
  ) : (
    <ChartSkeleton className="h-48" />
  )

  const maxDrawdownSlot =
    isPro && showDrawdown ? (
      <DashboardMaxDrawdown
        variant="compact"
        maxDrawdown={maxDrawdown}
        totalTrades={totalTrades}
      />
    ) : null

  const desktopEquity =
    showEquity && deferredSectionsReady ? (
      <DashboardEquityCurve
        variant="desktop"
        isPro={isPro}
        data={equityData}
        profitFactor={isPro ? profitFactor : undefined}
        currentStreak={isPro ? currentStreak : undefined}
        avgDay={isPro ? avgDay : undefined}
        consistency={isPro ? consistency : undefined}
        totalTrades={totalTrades}
        drawdownLimitLineY={drawdownLimitLineY}
        equityCurveUsesAccountBalance={equityCurveUsesAccountBalance}
        showPersonalDrawdownFloor={showPersonalDrawdownFloor}
      />
    ) : showEquity ? (
      <ChartSkeleton className="h-72" />
    ) : null

  const desktopSide = isPro ? (
    <div className="grid grid-cols-1 gap-2 md:gap-3 lg:grid-cols-2">
      {showSessions ? (
        <>
          <div className="hidden md:block">{recentTrades}</div>
          <div className="hidden md:block">{sessionChartDesktop}</div>
        </>
      ) : (
        <div className="hidden md:block lg:col-span-2">{recentTrades}</div>
      )}
    </div>
  ) : null

  return (
    <div className="flex flex-col gap-2 max-md:gap-5 md:gap-3">
      {desktopEquity ? (
        <div className="tt-dash-hide-desktop-v1 hidden md:block">{desktopEquity}</div>
      ) : null}
      <div
        className={`grid gap-2 overflow-visible max-md:gap-2 md:gap-3 ${
          desktopSide ? "lg:grid-cols-3" : ""
        }`}
      >
        <DashboardStatsGrid
          isPro={isPro}
          totalTrades={totalTrades}
          winRate={winRate}
          avgRR={avgRR}
          avgMaxRrReached={avgMaxRrReached}
          totalPnL={totalPnL}
          profitFactor={profitFactor}
          avgWin={avgWin}
          bestTrade={bestTrade}
          avgLoss={avgLoss}
          biggestLoss={biggestLoss}
          bestDay={bestDay}
          worstDay={worstDay}
          periodTradingDayCount={periodTradingDayCount}
          showEquity={showEquity}
          mobileEquitySlot={mobileEquity}
          expectancyData={expectancyData}
          streakData={streakData}
          hourData={hourData}
          showSessions={showSessions}
          bestWinStreak={bestWinStreak}
          maxDrawdownSlot={maxDrawdownSlot}
          liveAccountValue={liveAccountValue}
          timeframeLabel={timeframeLabel}
          heroDisplayValue={lastEquityPointValue(equityData)}
          equityCurveUsesAccountBalance={equityCurveUsesAccountBalance}
        />

        {desktopSide ? (
          <div className="tt-dash-hide-desktop-v1 hidden space-y-2 overflow-visible md:block md:space-y-3 lg:col-span-2">
            {desktopSide}
          </div>
        ) : null}
      </div>

      {isPro && mobileProTabs ? (
        <DashboardMobileProTabs
          {...mobileProTabs}
          deferredSectionsReady={deferredSectionsReady}
          weekdaySlot={weekdayChart}
          sessionsSlot={sessionChartMobile}
          showSessions={showSessions}
          hourData={hourData}
          maxDrawdown={maxDrawdown}
          avgWin={avgWin}
          bestTrade={bestTrade}
          avgLoss={avgLoss}
          biggestLoss={biggestLoss}
          payoutsTotal={payoutsTotal}
          winRate={winRate}
          winCount={winCount}
          lossCount={lossCount}
          rrTargetAnalysis={rrTargetAnalysis ?? EMPTY_RR_TARGET}
          totalTrades={totalTrades}
        />
      ) : null}
    </div>
  )
}

export default memo(DashboardCharts)
