"use client"

import { useEffect, useRef } from "react"
import { usePathname } from "next/navigation"
import { supabase } from "@/lib/supabaseClient"
import { useUserProfile } from "@/lib/UserProfileProvider"
import {
  configureProductAnalytics,
  productAnalyticsAppOpened,
  productAnalyticsFeatureUsed,
  productAnalyticsProfileViewed,
  productAnalyticsScreenViewed,
  productAnalyticsSessionStarted,
  flushProductAnalytics,
} from "@/lib/productAnalytics/tracker"
import {
  featureKeyFromScreen,
  screenIdFromPathname,
} from "@/lib/productAnalytics/screenFromPathname"
import { PRODUCT_ANALYTICS_SCREENS } from "@/lib/productAnalytics/constants"

/** Authenticated product analytics — fire-and-forget, never blocks UI. */
export default function ProductAnalyticsBridge() {
  const pathname = usePathname()
  const { user, profile } = useUserProfile()
  const userId = user?.id as string | undefined
  const lastScreenRef = useRef<string | null>(null)
  const lastProfileRef = useRef<string | null>(null)

  useEffect(() => {
    configureProductAnalytics(supabase)
  }, [])

  useEffect(() => {
    if (!userId) return
    productAnalyticsSessionStarted()
    productAnalyticsAppOpened()
  }, [userId])

  useEffect(() => {
    if (!userId) return
    const screenId = screenIdFromPathname(pathname ?? "")
    if (screenId === lastScreenRef.current) return
    lastScreenRef.current = screenId
    if (screenId === PRODUCT_ANALYTICS_SCREENS.unknown) return
    productAnalyticsScreenViewed(screenId)
    const feature = featureKeyFromScreen(screenId)
    if (feature) productAnalyticsFeatureUsed(feature)
  }, [pathname, userId])

  useEffect(() => {
    if (!userId || !pathname) return
    const screenId = screenIdFromPathname(pathname)
    if (screenId !== PRODUCT_ANALYTICS_SCREENS.profileOther) return
    const parts = pathname.split("/").filter(Boolean)
    const profileSegment = parts[0] === "profile" ? parts[1] : parts[0]
    if (!profileSegment) return
    if (userId && profileSegment === userId) return
    if (profile?.username && profileSegment.toLowerCase() === profile.username.toLowerCase()) {
      return
    }
    const uuidLike = /^[0-9a-f-]{36}$/i.test(profileSegment)
    if (!uuidLike) return
    const cacheKey = `${profileSegment}:${pathname}`
    if (lastProfileRef.current === cacheKey) return
    lastProfileRef.current = cacheKey
    productAnalyticsProfileViewed(profileSegment)
  }, [pathname, profile?.username, userId])

  useEffect(() => {
    return () => {
      void flushProductAnalytics()
    }
  }, [])

  return null
}