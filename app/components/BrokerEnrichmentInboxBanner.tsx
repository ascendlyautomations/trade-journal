"use client"

import { useCallback, useEffect, useState } from "react"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { getCachedTrades } from "@/lib/appDataCache"
import { supabase } from "@/lib/supabaseClient"
import {
  ensureBrokerEnrichmentPendingCountLoaded,
  subscribeBrokerEnrichmentPendingCountRefresh,
} from "@/lib/brokerEnrichment/brokerEnrichmentPendingCount"
import { queueBrokerEnrichment } from "@/lib/brokerEnrichment/queueBrokerEnrichment"

export default function BrokerEnrichmentInboxBanner() {
  const { user } = useUserProfile()
  const [count, setCount] = useState(0)
  const [loadingReview, setLoadingReview] = useState(false)

  const refresh = useCallback(async () => {
    if (!user?.id) {
      setCount(0)
      return
    }
    const n = await ensureBrokerEnrichmentPendingCountLoaded(supabase, user.id, {
      force: true,
    })
    setCount(n)
  }, [user?.id])

  useEffect(() => {
    void refresh()
    if (!user?.id) return
    return subscribeBrokerEnrichmentPendingCountRefresh(user.id, () => {
      void refresh()
    })
  }, [refresh, user?.id])

  async function handleReview() {
    if (!user?.id || loadingReview) return
    setLoadingReview(true)
    const cached = getCachedTrades(user.id) ?? []
    const ids = cached
      .filter(
        (row) =>
          String(row.import_source ?? "") === "tradovate" &&
          row.broker_enrichment_status === "pending"
      )
      .map((row) => String(row.id ?? ""))
      .filter((id) => id.length > 0)
      .slice(0, 50)

    setLoadingReview(false)
    if (ids.length === 0) {
      void refresh()
      return
    }
    queueBrokerEnrichment(ids)
  }

  if (!user?.id || count <= 0) return null

  return (
    <div className="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-blue-400/30 bg-blue-500/10 px-4 py-3">
      <p className="text-sm text-blue-100">
        {count} imported trade{count === 1 ? "" : "s"} need details
      </p>
      <button
        type="button"
        className="rounded-lg bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-500 disabled:opacity-50"
        disabled={loadingReview}
        onClick={() => void handleReview()}
      >
        Review
      </button>
    </div>
  )
}
