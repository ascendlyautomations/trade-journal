"use client"

import { useCallback, useEffect, useState } from "react"
import { useUserProfile } from "@/lib/UserProfileProvider"
import BrokerTradeEnrichmentModal from "@/app/components/BrokerTradeEnrichmentModal"
import { fetchBrokerEnrichmentTradesByIds } from "@/lib/brokerEnrichment/brokerEnrichmentApi"
import { BROKER_ENRICHMENT_QUEUE_EVENT } from "@/lib/brokerEnrichment/brokerEnrichmentTypes"
import { invalidateBrokerEnrichmentPendingCount } from "@/lib/brokerEnrichment/brokerEnrichmentPendingCount"
import { invalidateTradesCache } from "@/lib/appDataCache"
import { supabase } from "@/lib/supabaseClient"
import type { BrokerEnrichmentTradeRow } from "@/lib/brokerEnrichment/brokerEnrichmentTypes"

export default function BrokerEnrichmentBridge() {
  const { user } = useUserProfile()
  const [open, setOpen] = useState(false)
  const [trades, setTrades] = useState<BrokerEnrichmentTradeRow[]>([])
  const [index, setIndex] = useState(0)
  const [importCountLabel, setImportCountLabel] = useState<string | null>(null)

  const startQueue = useCallback(
    async (tradeIds: string[], options?: { countLabel?: string }) => {
      if (!user?.id) return
      const rows = await fetchBrokerEnrichmentTradesByIds(supabase, user.id, tradeIds)
      if (rows.length === 0) return

      invalidateTradesCache(user.id)
      invalidateBrokerEnrichmentPendingCount(user.id)

      setImportCountLabel(
        options?.countLabel ??
          `${rows.length} trade${rows.length === 1 ? "" : "s"} imported`
      )
      setTrades(rows)
      setIndex(0)
      setOpen(true)
    },
    [user?.id]
  )

  useEffect(() => {
    function onQueue(ev: Event) {
      const detail = (ev as CustomEvent<{ tradeIds?: string[] }>).detail
      const ids = detail?.tradeIds ?? []
      if (ids.length === 0) return
      void startQueue(ids, {
        countLabel: `${ids.length} trade${ids.length === 1 ? "" : "s"} imported`,
      })
    }

    window.addEventListener(BROKER_ENRICHMENT_QUEUE_EVENT, onQueue)
    return () => window.removeEventListener(BROKER_ENRICHMENT_QUEUE_EVENT, onQueue)
  }, [startQueue])

  function handleAdvance(_completedId: string) {
    if (!user?.id) return
    invalidateTradesCache(user.id)
    invalidateBrokerEnrichmentPendingCount(user.id)

    const next = index + 1
    if (next < trades.length) {
      setIndex(next)
      return
    }
    setOpen(false)
    setTrades([])
    setIndex(0)
    setImportCountLabel(null)
  }

  function handleClose() {
    setOpen(false)
    setTrades([])
    setIndex(0)
    setImportCountLabel(null)
  }

  if (!user?.id) return null

  return (
    <BrokerTradeEnrichmentModal
      open={open}
      trades={trades}
      index={index}
      userId={user.id}
      importCountLabel={importCountLabel}
      onClose={handleClose}
      onAdvance={handleAdvance}
    />
  )
}
