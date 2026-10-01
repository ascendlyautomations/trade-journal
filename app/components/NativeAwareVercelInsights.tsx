"use client"

import { useEffect, useState, type ComponentType } from "react"
import {
  COOKIE_CONSENT_CHANGED_EVENT,
  isAnalyticsAllowed,
} from "@/lib/cookieConsent"
import { isNativePlatform } from "@/lib/nativePlatform"

function isVercelHostedRuntime(): boolean {
  if (process.env.NEXT_PUBLIC_VERCEL === "1") return true
  if (process.env.VERCEL === "1") return true
  if (typeof window !== "undefined") {
    return /vercel\.app$/i.test(window.location.hostname)
  }
  return false
}

/**
 * Vercel Analytics + Speed Insights — deployed web only, when user allows analytics.
 * Skips native shells and local `next start` (avoids /_vercel/* 404 noise).
 */
export default function NativeAwareVercelInsights() {
  const [analyticsAllowed, setAnalyticsAllowed] = useState(false)
  const [Insights, setInsights] = useState<{
    Analytics: ComponentType
    SpeedInsights: ComponentType
  } | null>(null)

  useEffect(() => {
    if (isNativePlatform()) return
    if (!isVercelHostedRuntime()) return

    function syncAllowed() {
      setAnalyticsAllowed(isAnalyticsAllowed())
    }

    syncAllowed()
    window.addEventListener(COOKIE_CONSENT_CHANGED_EVENT, syncAllowed)
    window.addEventListener("storage", syncAllowed)
    return () => {
      window.removeEventListener(COOKIE_CONSENT_CHANGED_EVENT, syncAllowed)
      window.removeEventListener("storage", syncAllowed)
    }
  }, [])

  useEffect(() => {
    if (!analyticsAllowed) {
      setInsights(null)
      return
    }
    if (isNativePlatform()) return
    if (!isVercelHostedRuntime()) return

    let cancelled = false
    void Promise.all([
      import("@vercel/analytics/next"),
      import("@vercel/speed-insights/next"),
    ]).then(([analytics, speed]) => {
      if (cancelled) return
      setInsights({
        Analytics: analytics.Analytics,
        SpeedInsights: speed.SpeedInsights,
      })
    })
    return () => {
      cancelled = true
    }
  }, [analyticsAllowed])

  if (!analyticsAllowed || !Insights) return null

  const { Analytics, SpeedInsights } = Insights
  return (
    <>
      <Analytics />
      <SpeedInsights />
    </>
  )
}
