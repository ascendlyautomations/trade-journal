"use client"

import { useCallback, useEffect, useState } from "react"
import { usePathname } from "next/navigation"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { isAppAddTradePath } from "@/lib/addTradePath"
import { CONTEXTUAL_TOUR_DASHBOARD } from "@/lib/contextualTour/catalog"
import { hasContextualTourAwaitingInvite } from "@/lib/contextualTour/awaitingInvite"
import { useContextualTourOptional } from "@/lib/contextualTour/ContextualTourProvider"
import { dismissedVersion } from "@/lib/contextualTour/progressStore"
import { supabase } from "@/lib/supabaseClient"
import {
  fetchHasJournalTrade,
  fetchTradingPreferenceDiscovery,
  fetchTradingPreferencesConfigured,
  preferenceDiscoveryPlacement,
  preferenceTourEligible,
  recordTradingPreferenceDiscovery,
  type PreferenceDiscoveryPlacement,
  type PreferenceDiscoveryResponse,
} from "@/lib/analytics/preferenceDiscovery"

const quietDashboardHoldKey = "tt.analyticsPref.quietDashboardHold"

type Options = {
  userId: string | null | undefined
  hasTrade?: boolean
  tradesReady?: boolean
}

export function useTradingPreferenceDiscovery({
  userId,
  hasTrade,
  tradesReady = true,
}: Options) {
  const pathname = usePathname()
  const tour = useContextualTourOptional()
  const [ready, setReady] = useState(false)
  const [configured, setConfigured] = useState(false)
  const [response, setResponse] = useState<PreferenceDiscoveryResponse | null>(null)
  const [remoteHasTrade, setRemoteHasTrade] = useState(false)
  const [tourEligible, setTourEligible] = useState(false)
  const [holdQuietDashboard, setHoldQuietDashboard] = useState(false)

  useEffect(() => {
    if (!userId || isDemoModeActive()) {
      setReady(true)
      setConfigured(false)
      setResponse(null)
      return
    }
    let cancelled = false
    setReady(false)
    void (async () => {
      try {
        const [nextResponse, nextConfigured, nextHasTrade, profile] = await Promise.all([
          fetchTradingPreferenceDiscovery(supabase, userId),
          fetchTradingPreferencesConfigured(supabase, userId),
          hasTrade == null ? fetchHasJournalTrade(supabase, userId) : Promise.resolve(hasTrade),
          supabase.from("profiles").select("created_at").eq("id", userId).maybeSingle(),
        ])
        if (cancelled) return
        setResponse(nextResponse)
        setConfigured(nextConfigured)
        setRemoteHasTrade(nextHasTrade)
        const createdAt =
          profile.data && typeof profile.data.created_at === "string"
            ? profile.data.created_at
            : null
        setTourEligible(preferenceTourEligible(createdAt))
      } catch {
        if (!cancelled) {
          setConfigured(false)
          setResponse(null)
        }
      } finally {
        if (!cancelled) setReady(true)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [hasTrade, userId])

  const knownHasTrade = hasTrade ?? remoteHasTrade
  const tourSettled =
    !!userId &&
    dismissedVersion(userId, CONTEXTUAL_TOUR_DASHBOARD.id) >=
      CONTEXTUAL_TOUR_DASHBOARD.version
  const tourBlocking = Boolean(
    isAppAddTradePath(pathname) ||
      tour?.showInvite ||
      tour?.isActive ||
      (userId && hasContextualTourAwaitingInvite(userId) && !tourSettled)
  )

  const placement: PreferenceDiscoveryPlacement | null =
    ready && tradesReady && userId && !isDemoModeActive()
      ? preferenceDiscoveryPlacement({
          configured,
          response,
          tourEligible,
          tourSettled,
          tourBlocking,
          hasTrade: knownHasTrade,
        })
      : null

  const record = useCallback(
    async (next: PreferenceDiscoveryResponse) => {
      if (!userId) return
      setResponse((current) => {
        if (current === "completed") return current
        if (current === "dismissed" && next !== "completed") return current
        if (current === "skipped" && next === "skipped") return current
        return next
      })
      if (next === "skipped") {
        setHoldQuietDashboard(true)
        try {
          sessionStorage.setItem(quietDashboardHoldKey, userId)
        } catch {
          // ignore private mode
        }
      }
      try {
        const saved = await recordTradingPreferenceDiscovery(supabase, userId, next)
        setResponse(saved)
        if (saved === "completed") setConfigured(true)
      } catch {
        // The in-memory response still hides the invitation for this visit.
      }
    },
    [userId]
  )

  useEffect(() => {
    if (!userId) return
    try {
      setHoldQuietDashboard(sessionStorage.getItem(quietDashboardHoldKey) === userId)
    } catch {
      setHoldQuietDashboard(false)
    }
  }, [userId])

  return {
    placement,
    dashboardPlacement:
      placement === "quiet" && holdQuietDashboard ? null : placement,
    record,
  }
}
