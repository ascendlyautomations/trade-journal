"use client"

import { useCallback, useEffect, useState } from "react"

export const DASHBOARD_MOBILE_TABS = ["overview", "analytics", "records"] as const

export type DashboardMobileTab = (typeof DASHBOARD_MOBILE_TABS)[number]

const STORAGE_KEY = "tt-dashboard-mobile-tab"

function isDashboardMobileTab(value: unknown): value is DashboardMobileTab {
  return (
    value === "overview" || value === "analytics" || value === "records"
  )
}

/** Default Overview for first visit; persist last tab for returning users. */
export function useDashboardMobileTab() {
  const [tab, setTabState] = useState<DashboardMobileTab>("overview")
  const [hydrated, setHydrated] = useState(false)

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY)
      if (isDashboardMobileTab(raw)) setTabState(raw)
    } catch {
      /* ignore */
    }
    setHydrated(true)
  }, [])

  const setTab = useCallback((next: DashboardMobileTab) => {
    setTabState(next)
    try {
      window.localStorage.setItem(STORAGE_KEY, next)
    } catch {
      /* ignore */
    }
  }, [])

  return { tab, setTab, hydrated }
}
