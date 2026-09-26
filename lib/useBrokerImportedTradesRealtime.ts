"use client"

import { useEffect } from "react"
import { supabase } from "@/lib/supabaseClient"
import {
  applyBrokerImportedTradeToCache,
  ensureTradesLoaded,
} from "@/lib/appDataCache"
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
          const nextRow = payload.new as {
            id?: string
            import_source?: string | null
            broker_enrichment_status?: string | null
          } | null
          const previousRow = payload.old as {
            id?: string
            import_source?: string | null
          } | null
          const eventType = payload.eventType
          if (eventType !== "DELETE") {
            const src = nextRow?.import_source
            if (src !== "tradovate" && src !== "rithmic") return
          }
          const applied = applyBrokerImportedTradeToCache(
            userId,
            eventType,
            nextRow as Record<string, unknown> | null,
            previousRow as Record<string, unknown> | null
          )
          if (applied.needsWindowLoad) {
            void ensureTradesLoaded(supabase, userId)
          }
          if (
            eventType === "INSERT" &&
            nextRow?.broker_enrichment_status === "pending" &&
            nextRow.id
          ) {
            invalidateBrokerEnrichmentPendingCount(userId)
            queueBrokerEnrichment([String(nextRow.id)])
          }
        }
      )
      .subscribe()

    return () => {
      void supabase.removeChannel(channel)
    }
  }, [userId])
}
