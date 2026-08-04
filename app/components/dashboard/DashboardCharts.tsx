"use client"

import dynamic from "next/dynamic"
import { memo, type ComponentProps, type ReactNode } from "react"
import DashboardMobileProTabs from "./DashboardMobileProTabs"
import DashboardStatsGrid from "./DashboardStatsGrid"

const DashboardEquityCurve = dynamic(() => import("./DashboardEquityCurve"), {
  loading: () => <div className="h-48 animate-pulse rounded-lg bg-white/5" />,
})
const DashboardWeekdayChart = dynamic(() => import("./DashboardWeekdayChart"), {
  loading: () => <div className="h-48 animate-pulse rounded-lg bg-white/5" />,
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
  | "maxDrawdownSlot"
  | "recentTrades"
  | "streakData"
  | "hourData"
  | "bestWinStreak"
  | "showSessions"
  | "avgWin"
  | "bestTrade"
  | "avgLoss"
  | "biggestLoss"
  | "bestDay"
  | "worstDay"
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
  weekdayData: ComponentProps<typeof DashboardWeekdayChart>["data"]
  sessionPieData: ComponentProps<typeof DashboardSessionChart>["sessionPieData"]
  sessionBuckets: ComponentProps<typeof DashboardSessionChart>["sessionBuckets"]
  maxDrawdown: ComponentProps<typeof DashboardMaxDrawdown>["maxDrawdown"]
  showDrawdown: boolean
  currentStreak: number
  avgDay: number
  consistency: number
  recentTrades: ReactNode
  /** When set, Pro mobile renders Overview / Analytics / Records tabs. */
  mobileProTabs?: MobileProTabsProps
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
  totalPnL,
  profitFactor,
  avgWin,
  bestTrade,
  avgLoss,
  biggestLoss,
  bestDay,
  worstDay,
  showEquity,
  expectancyData,
  streakData,
  hourData,
  showSessions,
  bestWinStreak,
  mobileProTabs,
}: DashboardChartsProps) {
  const weekdayChart = deferredSectionsReady ? (
    <DashboardWeekdayChart data={weekdayData} totalTrades={totalTrades} />
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
    <DashboardSessionChart
      variant="mobile"
      sessionPieData={sessionPieData}
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

  return (
    <div className="flex flex-col gap-2 max-md:gap-2 md:contents">
      <div className="grid gap-2 overflow-visible max-md:gap-2 md:gap-3 lg:grid-cols-3">
        <DashboardStatsGrid
          isPro={isPro}
          totalTrades={totalTrades}
          winRate={winRate}
          avgRR={avgRR}
          totalPnL={totalPnL}
          profitFactor={profitFactor}
          avgWin={avgWin}
          bestTrade={bestTrade}
          avgLoss={avgLoss}
          biggestLoss={biggestLoss}
          bestDay={bestDay}
          worstDay={worstDay}
          showEquity={showEquity}
          mobileEquitySlot={mobileEquity}
          expectancyData={expectancyData}
          streakData={streakData}
          hourData={hourData}
          showSessions={showSessions}
          bestWinStreak={bestWinStreak}
          maxDrawdownSlot={maxDrawdownSlot}
        />

        <div className="hidden space-y-2 overflow-visible md:block md:space-y-3 lg:col-span-2">
          {showEquity && deferredSectionsReady ? (
            <DashboardEquityCurve
              variant="desktop"
              isPro={isPro}
              data={equityData}
              profitFactor={isPro ? profitFactor : undefined}
              currentStreak={isPro ? currentStreak : undefined}
              avgDay={isPro ? avgDay : undefined}
              consistency={isPro ? consistency : undefined}
              totalTrades={totalTrades}
            />
          ) : showEquity ? (
            <ChartSkeleton className="h-72" />
          ) : null}

          {isPro ? (
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
          ) : null}
        </div>
      </div>

      {isPro && mobileProTabs ? (
        <DashboardMobileProTabs
          {...mobileProTabs}
          deferredSectionsReady={deferredSectionsReady}
          weekdaySlot={weekdayChart}
          sessionsSlot={sessionChartMobile}
          showSessions={showSessions}
          hourData={hourData}
          streakData={streakData}
          bestWinStreak={bestWinStreak}
          maxDrawdownSlot={maxDrawdownSlot}
          recentTrades={recentTrades}
          avgWin={avgWin}
          bestTrade={bestTrade}
          avgLoss={avgLoss}
          biggestLoss={biggestLoss}
          bestDay={bestDay}
          worstDay={worstDay}
          totalTrades={totalTrades}
        />
      ) : null}
    </div>
  )
}

export default memo(DashboardCharts)
