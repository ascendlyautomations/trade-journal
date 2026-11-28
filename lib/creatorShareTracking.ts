import type { SupabaseClient } from "@supabase/supabase-js"
import { isBackendV2Enabled } from "@/lib/backendV2/flags"

export type CreatorSharePhase = "initiated" | "completed"

export type CreatorShareItem = {
  content_kind: string
  content_id: string
  share_phase: CreatorSharePhase
  platform?: "web" | "ios"
}

function trackingEnabled(): boolean {
  return (
    isBackendV2Enabled("feedRotatingRank") ||
    isBackendV2Enabled("profileInsights")
  )
}

export function resolveWebShareTarget(args: {
  feedKind?: "trade" | "profile" | "achievement" | "reel"
  postId?: string | null
  profileId?: string | null
}): { content_kind: string; content_id: string } | null {
  if (args.profileId) {
    return { content_kind: "trader_profile", content_id: args.profileId }
  }
  if (args.postId) {
    const kind =
      args.feedKind === "profile"
        ? "profile_post"
        : args.feedKind === "achievement"
          ? "achievement_post"
          : args.feedKind === "reel"
            ? "reel"
            : "post"
    return { content_kind: kind, content_id: args.postId }
  }
  return null
}

export async function recordCreatorShares(
  client: SupabaseClient,
  items: CreatorShareItem[]
): Promise<void> {
  if (!trackingEnabled() || items.length === 0) return
  const payload = items.map((item) => ({
    content_kind: item.content_kind,
    content_id: item.content_id,
    share_phase: item.share_phase,
    platform: item.platform ?? "web",
  }))
  const { error } = await client.rpc("rpc_v1_creator_record_shares", {
    p_items: payload,
  })
  if (error) {
    console.warn("[creator.shares] record failed", error.message)
  }
}