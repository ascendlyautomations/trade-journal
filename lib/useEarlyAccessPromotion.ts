"use client"

import { useEffect, useState } from "react"

let cachedEnabled: boolean | null = null
let inFlight: Promise<boolean> | null = null

async function loadPromotionEnabled(): Promise<boolean> {
  if (cachedEnabled != null) return cachedEnabled
  if (!inFlight) {
    inFlight = fetch("/api/early-access/config", { cache: "no-store" })
      .then(async (response) => {
        if (!response.ok) return false
        const body = (await response.json()) as { enabled?: boolean }
        return body.enabled === true
      })
      .catch(() => false)
      .then((enabled) => {
        cachedEnabled = enabled
        return enabled
      })
      .finally(() => {
        inFlight = null
      })
  }
  return inFlight
}

export function useEarlyAccessPromotion(): {
  enabled: boolean
  loading: boolean
} {
  // Conservative initial state prevents a pricing flash while enabled.
  const [enabled, setEnabled] = useState(cachedEnabled ?? true)
  const [loading, setLoading] = useState(cachedEnabled == null)

  useEffect(() => {
    let cancelled = false
    void loadPromotionEnabled().then((next) => {
      if (cancelled) return
      setEnabled(next)
      setLoading(false)
    })
    return () => {
      cancelled = true
    }
  }, [])

  return { enabled, loading }
}

export function clearEarlyAccessPromotionCache() {
  cachedEnabled = null
}
