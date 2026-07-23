"use client"

import { useEffect, useState, type ComponentType } from "react"
import { isNativePlatform } from "@/lib/nativePlatform"

/**
 * Vercel Analytics + Speed Insights for web only.
 * Capacitor/native never downloads or initializes either package.
 */
export default function NativeAwareVercelInsights() {
  const [Insights, setInsights] = useState<{
    Analytics: ComponentType
    SpeedInsights: ComponentType
  } | null>(null)

  useEffect(() => {
    if (isNativePlatform()) return
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
  }, [])

  if (!Insights) return null

  const { Analytics, SpeedInsights } = Insights
  return (
    <>
      <Analytics />
      <SpeedInsights />
    </>
  )
}
