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
import { syncDemoBannerLayout } from "@/lib/demo/demoLayout"

function DemoBannerInset({ children }: { children: ReactNode }) {
  const pathname = usePathname()
  const standaloneFlow = isStandaloneFlowRoute(pathname)
  const { user, profile, loading } = useUserProfile()
  const [demoMode, setDemoMode] = useState(false)

  const bannerVisible =
    demoMode &&
    !standaloneFlow &&
    !shouldShowCustomerHomeChrome(user, profile, loading)

  useEffect(() => {
    const sync = () => {
      setDemoMode(isDemoModeActive())
    }
    sync()
    return subscribeDemoModeChanges(sync)
  }, [])

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
