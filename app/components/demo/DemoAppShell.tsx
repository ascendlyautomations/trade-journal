"use client"

import { usePathname } from "next/navigation"
import { useEffect, useState, type ReactNode } from "react"
import DemoBanner from "@/app/demo/components/DemoBanner"
import { DemoModeProvider } from "@/lib/demo/DemoModeContext"
import { isStandaloneFlowRoute } from "@/lib/authRoutes"
import { shouldShowCustomerHomeChrome } from "@/lib/marketingAccess"
import { useUserProfile } from "@/lib/useUserProfile"
import {
  isDemoModeActive,
  subscribeDemoModeChanges,
} from "@/lib/demo/demoMode"
import {
  GUEST_EXPLORE_CHANGE_EVENT,
  isGuestExploreViewer,
} from "@/lib/guestExplore"
import { syncDemoBannerLayout } from "@/lib/demo/demoLayout"

function DemoBannerInset({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const standaloneFlow = isStandaloneFlowRoute(pathname)
  const { user, profile, loading } = useUserProfile()
  const [demoMode, setDemoMode] = useState(false)
  const [guestExplore, setGuestExplore] = useState(false)

  const bannerVisible =
    (demoMode || guestExplore) &&
    !standaloneFlow &&
    !shouldShowCustomerHomeChrome(user, profile, loading)

  useEffect(() => {
    const sync = () => {
      setDemoMode(isDemoModeActive())
      setGuestExplore(isGuestExploreViewer(user))
    }
    sync()
    const unsubDemo = subscribeDemoModeChanges(sync)
    window.addEventListener(GUEST_EXPLORE_CHANGE_EVENT, sync)
    return () => {
      unsubDemo()
      window.removeEventListener(GUEST_EXPLORE_CHANGE_EVENT, sync)
    }
  }, [user])

  useEffect(() => {
    syncDemoBannerLayout(bannerVisible)
  }, [bannerVisible])

  useEffect(() => {
    if (standaloneFlow) {
      syncDemoBannerLayout(false)
    }
  }, [standaloneFlow])

  useEffect(() => {
    return () => syncDemoBannerLayout(false)
  }, [])

  return (
    <>
      {bannerVisible ? <DemoBanner /> : null}
      {children}
    </>
  )
}

export default function DemoAppShell({ children }: { children: ReactNode }) {
  return (
    <DemoModeProvider>
      <DemoBannerInset>{children}</DemoBannerInset>
    </DemoModeProvider>
  )
}
