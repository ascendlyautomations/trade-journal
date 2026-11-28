import type { SupabaseClient } from "@supabase/supabase-js"
import {
  queueFeedImpression,
  recordsCreatorContentViewsEnabled,
  type FeedImpressionItem,
} from "@/lib/feedImpressionRecorder"

export type CreatorContentSurface =
  | "feed"
  | "clips"
  | "profile"
  | "detail"
  | "story"

export function queueCreatorContentView(
  item: FeedImpressionItem & { surface?: CreatorContentSurface }
): void {
  if (!recordsCreatorContentViewsEnabled()) return
  queueFeedImpression({
    content_kind: item.content_kind,
    content_id: item.content_id,
    surface: item.surface ?? "detail",
  })
}

export async function flushCreatorContentViews(
  client?: SupabaseClient
): Promise<void> {
  if (!client) return
  const { flushFeedImpressionQueue } = await import("@/lib/feedImpressionRecorder")
  await flushFeedImpressionQueue(client)
}