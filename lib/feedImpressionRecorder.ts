import type { SupabaseClient } from "@supabase/supabase-js"
import { isBackendV2Enabled } from "@/lib/backendV2/flags"

export type FeedImpressionItem = {
  content_kind: string
  content_id: string
}

const pending = new Map<string, FeedImpressionItem>()
let flushTimer: ReturnType<typeof setTimeout> | null = null
let flushInFlight: Promise<void> | null = null

const FLUSH_DEBOUNCE_MS = 4_000
const MAX_BATCH = 50

function queueKey(item: FeedImpressionItem): string {
  return `${item.content_kind}|${item.content_id}`
}

export function queueFeedImpression(item: FeedImpressionItem): void {
  if (!isBackendV2Enabled("feedRotatingRank")) return
  pending.set(queueKey(item), item)
  scheduleFlush()
}

function scheduleFlush(): void {
  if (flushTimer) return
  flushTimer = setTimeout(() => {
    flushTimer = null
    void flushFeedImpressionQueue()
  }, FLUSH_DEBOUNCE_MS)
}

export async function flushFeedImpressionQueue(
  client?: SupabaseClient
): Promise<void> {
  if (!client || pending.size === 0) return
  if (flushInFlight) {
    await flushInFlight
    return
  }
  flushInFlight = (async () => {
    while (pending.size > 0) {
      const batch = [...pending.values()].slice(0, MAX_BATCH)
      for (const row of batch) pending.delete(queueKey(row))
      try {
        const { error } = await client.rpc("rpc_v1_feed_record_impressions", {
          p_items: batch,
        })
        if (error) {
          console.warn("[feed.impressions] flush failed", error.message)
        }
      } catch (err) {
        console.warn("[feed.impressions] flush failed", err)
      }
    }
  })().finally(() => {
    flushInFlight = null
  })
  await flushInFlight
}