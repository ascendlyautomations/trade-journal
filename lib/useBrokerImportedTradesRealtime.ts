"use client"

import { useEffect } from "react"
import { supabase } from "@/lib/supabaseClient"
import { invalidateTradesCache, ensureTradesLoaded } from "@/lib/appDataCache"
import { queueBrokerEnrichment } from "@/lib/brokerEnrichment/queueBrokerEnrichment"
import { invalidateBrokerEnrichmentPendingCount } from "@/lib/brokerEnrichment/brokerEnrichmentPendingCount"

/**
 * When the broker-sync worker inserts/updates canonical trades server-side,
 * refresh the in-memory trades cache for the signed-in user (no polling).
 */
export function useBrokerImportedTradesRealtime(userId: string | undefined) {
  useEffect(() => {
    if (!userId) return

    const channel = supabase
      .channel(`broker-trades-${userId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "trades",
          filter: `user_id=eq.${userId}`,
        },
        (payload) => {
          const row = payload.new as {
            id?: string
            import_source?: string | null
            broker_enrichment_status?: string | null
          } | null
          if (row?.import_source !== "tradovate") return
          invalidateTradesCache(userId)
          void ensureTradesLoaded(supabase, userId, { force: true, fullHistory: true })
          if (
            payload.eventType === "INSERT" &&
            row.broker_enrichment_status === "pending" &&
            row.id
          ) {
            invalidateBrokerEnrichmentPendingCount(userId)
            queueBrokerEnrichment([String(row.id)])
          }
        }
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [userId])
}
