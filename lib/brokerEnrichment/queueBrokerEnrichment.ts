import { BROKER_ENRICHMENT_QUEUE_EVENT } from "@/lib/brokerEnrichment/brokerEnrichmentTypes"

/** Client-only: open the post-import enrichment flow for new trade ids. */
export function queueBrokerEnrichment(tradeIds: string[]): void {
  if (typeof window === "undefined") return
  const ids = [...new Set(tradeIds.map((id) => id.trim()).filter(Boolean))]
  if (ids.length === 0) return
  window.dispatchEvent(
    new CustomEvent(BROKER_ENRICHMENT_QUEUE_EVENT, { detail: { tradeIds: ids } })
  )
}
