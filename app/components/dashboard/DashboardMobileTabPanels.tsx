"use client"

import { useEffect, useRef, useState, type ReactNode } from "react"
import type { DashboardMobileTab } from "./useDashboardMobileTab"

type DashboardMobileTabPanelsProps = {
  activeTab: DashboardMobileTab
  overview: ReactNode
  analytics: ReactNode
  records: ReactNode
}

/**
 * Keep visited panels mounted (show/hide) so charts are not remounted on every
 * tab switch. First visit mounts while visible so Recharts can measure width.
 */
export default function DashboardMobileTabPanels({
  activeTab,
  overview,
  analytics,
  records,
}: DashboardMobileTabPanelsProps) {
  const [visited, setVisited] = useState<Record<DashboardMobileTab, boolean>>({
    overview: true,
    analytics: false,
    records: false,
  })
  const prevTabRef = useRef(activeTab)

  useEffect(() => {
    setVisited((prev) =>
      prev[activeTab] ? prev : { ...prev, [activeTab]: true }
    )
  }, [activeTab])

  useEffect(() => {
    if (prevTabRef.current === activeTab) return
    prevTabRef.current = activeTab
    const id = window.requestAnimationFrame(() => {
      window.dispatchEvent(new Event("resize"))
    })
    return () => window.cancelAnimationFrame(id)
  }, [activeTab])

  return (
    <div className="relative min-h-0">
      <TabPanel
        id="dashboard-mobile-panel-overview"
        tab="overview"
        activeTab={activeTab}
        mounted={visited.overview}
      >
        {overview}
      </TabPanel>
      <TabPanel
        id="dashboard-mobile-panel-analytics"
        tab="analytics"
        activeTab={activeTab}
        mounted={visited.analytics}
      >
        {analytics}
      </TabPanel>
      <TabPanel
        id="dashboard-mobile-panel-records"
        tab="records"
        activeTab={activeTab}
        mounted={visited.records}
      >
        {records}
      </TabPanel>
    </div>
  )
}

function TabPanel({
  id,
  tab,
  activeTab,
  mounted,
  children,
}: {
  id: string
  tab: DashboardMobileTab
  activeTab: DashboardMobileTab
  mounted: boolean
  children: ReactNode
}) {
  if (!mounted) return null

  const active = activeTab === tab

  return (
    <div
      id={id}
      role="tabpanel"
      aria-labelledby={`dashboard-mobile-tab-${tab}`}
      aria-hidden={!active}
      className={
        active
          ? "flex flex-col gap-2 motion-safe:animate-[ttDashTabFade_160ms_ease-out]"
          : "hidden"
      }
    >
      {children}
    </div>
  )
}
