"use client"

import { useCallback, type ComponentProps, type ReactNode } from "react"
import DashboardAnalytics from "./DashboardAnalytics"
import DashboardInsights from "./DashboardInsights"
import DashboardMobileSegmentedControl from "./DashboardMobileSegmentedControl"
import DashboardMobileTabPanels from "./DashboardMobileTabPanels"
import {
  DashboardRecordsStatsGrid,
  DashboardStreaksCard,
  DashboardTradingHoursCard,
} from "./DashboardStatsGrid"
import { useDashboardMobileTab } from "./useDashboardMobileTab"
import type { DashboardMobileTab } from "./useDashboardMobileTab"

type DashboardMobileProTabsProps = {
  deferredSectionsReady: boolean
  weekdaySlot: ReactNode
  sessionsSlot: ReactNode
  showSessions: boolean
  hourData: ComponentProps<typeof DashboardTradingHoursCard>["hourData"]
  streakData: ComponentProps<typeof DashboardStreaksCard>["streakData"]
  bestWinStreak: number
  maxDrawdownSlot: ReactNode
  recentTrades: ReactNode
  avgWin: number
  bestTrade: number
  avgLoss: number
  biggestLoss: number
  bestDay: number
  worstDay: number
  symbolPerformanceRows: ComponentProps<
    typeof DashboardAnalytics
  >["symbolPerformanceRows"]
  hasAnyTrades: boolean
  weekdayData: ComponentProps<typeof DashboardAnalytics>["weekdayData"]
  longShortPerformance: ComponentProps<
    typeof DashboardAnalytics
  >["longShortPerformance"]
  holdTimeStats: ComponentProps<typeof DashboardAnalytics>["holdTimeStats"]
  totalTrades: number
  insightsProps: ComponentProps<typeof DashboardInsights>
}

function getScrollRoot(): HTMLElement | Window {
  if (typeof document === "undefined") return window
  const el = document.querySelector("[data-tt-app-scroll]")
  if (el instanceof HTMLElement) return el
  return window
}

function readScrollTop(root: HTMLElement | Window): number {
  if (root === window) {
    return window.scrollY || document.documentElement.scrollTop || 0
  }
  return (root as HTMLElement).scrollTop
}

function writeScrollTop(root: HTMLElement | Window, top: number) {
  if (root === window) {
    document.documentElement.scrollTop = top
    document.body.scrollTop = top
    return
  }
  ;(root as HTMLElement).scrollTop = top
}

/**
 * Mobile-only Pro dashboard mode switcher. Desktop must not render this.
 */
export default function DashboardMobileProTabs({
  deferredSectionsReady,
  weekdaySlot,
  sessionsSlot,
  showSessions,
  hourData,
  streakData,
  bestWinStreak,
  maxDrawdownSlot,
  recentTrades,
  avgWin,
  bestTrade,
  avgLoss,
  biggestLoss,
  bestDay,
  worstDay,
  symbolPerformanceRows,
  hasAnyTrades,
  weekdayData,
  longShortPerformance,
  holdTimeStats,
  totalTrades,
  insightsProps,
}: DashboardMobileProTabsProps) {
  const { tab, setTab } = useDashboardMobileTab()

  const handleTabChange = useCallback(
    (next: DashboardMobileTab) => {
      if (next === tab) return
      const root = getScrollRoot()
      // Preserve scroll offset — do not re-anchor the control in the viewport
      // (that created empty space above the first card on shorter tabs).
      const scrollTop = readScrollTop(root)
      setTab(next)
      window.requestAnimationFrame(() => {
        window.requestAnimationFrame(() => {
          writeScrollTop(root, scrollTop)
        })
      })
    },
    [setTab, tab]
  )

  return (
    <div className="flex flex-col gap-2 md:hidden">
      <div className="tt-dashboard-tab-sticky sticky z-30 -mx-0 bg-[var(--tt-surface,#0b1f3a)]/95 py-0 backdrop-blur-md">
        <DashboardMobileSegmentedControl value={tab} onChange={handleTabChange} />
      </div>

      <DashboardMobileTabPanels
        activeTab={tab}
        overview={
          <>
            <DashboardInsights {...insightsProps} sections="performance" />
            {maxDrawdownSlot}
            <DashboardStreaksCard
              streakData={streakData}
              bestWinStreak={bestWinStreak}
            />
            {recentTrades}
          </>
        }
        analytics={
          <>
            {weekdaySlot}
            {showSessions ? sessionsSlot : null}
            <DashboardTradingHoursCard hourData={hourData} />
            <DashboardAnalytics
              symbolPerformanceRows={symbolPerformanceRows}
              hasAnyTrades={hasAnyTrades}
              deferredSectionsReady={deferredSectionsReady}
              weekdayData={weekdayData}
              longShortPerformance={longShortPerformance}
              holdTimeStats={holdTimeStats}
              totalTrades={totalTrades}
              longShortLayout="compare"
            />
          </>
        }
        records={
          <>
            <DashboardRecordsStatsGrid
              avgWin={avgWin}
              bestTrade={bestTrade}
              avgLoss={avgLoss}
              biggestLoss={biggestLoss}
              bestDay={bestDay}
              worstDay={worstDay}
            />
            <DashboardInsights {...insightsProps} sections="records" />
          </>
        }
      />
    </div>
  )
}
