"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import type { PreferenceRuleContext } from "@/lib/analytics/preferenceCompliance"
import {
  buildTradingRulesComplianceAnalytics,
  complianceTradesFromRows,
  type TradingRulesComplianceAnalytics,
} from "@/lib/analytics/tradingRulesComplianceAnalytics"
import {
  loadTradingPreferenceBundle,
} from "@/lib/analytics/tradingPreferencesStore"
import { supabase } from "@/lib/supabaseClient"

export function useTradingRulesCompliance(
  userId: string | null | undefined,
  trades: readonly Record<string, unknown>[],
  enabled: boolean
) {
  const [context, setContext] = useState<PreferenceRuleContext | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    if (!userId || !enabled) return
    setLoading(true)
    setError(null)
    try {
      setContext(await loadTradingPreferenceBundle(supabase, userId))
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load trading rules.")
      setContext(null)
    } finally {
      setLoading(false)
    }
  }, [enabled, userId])

  useEffect(() => {
    if (!enabled || !userId) {
      setContext(null)
      return
    }
    void load()
  }, [enabled, load, userId])

  const analytics: TradingRulesComplianceAnalytics | null = useMemo(() => {
    if (!enabled || !context) return null
    const rows = complianceTradesFromRows(trades)
    if (rows.length === 0) return null
    return buildTradingRulesComplianceAnalytics(rows, context)
  }, [context, enabled, trades])

  return { analytics, loading, error, context, reload: load }
}
