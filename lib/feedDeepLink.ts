import type { SupabaseClient } from "@supabase/supabase-js"
import type { FeedItem } from "@/app/components/feed/feedPostHelpers"
import { fetchAchievementPostById } from "@/lib/achievementPostEngagement"
import {
  fetchProfileFeedPostById,
  fetchTradeFeedPostById,
  fetchTradeFeedPostByTradeId,
} from "@/lib/feedContent"
import { fetchReelFeedPostById } from "@/lib/reelEngagement"

export type FeedDeepLinkKind = "post" | "trade" | "achievement" | "reel"

export type FeedDeepLinkTarget = {
  kind: FeedDeepLinkKind
  id: string
  openComments: boolean
}

/** Parse `/feed` query params into a deep-link target (content-type agnostic). */
export function parseFeedDeepLinkTarget(
  searchParams: Pick<URLSearchParams, "get">
): FeedDeepLinkTarget | null {
  const openComments = searchParams.get("comments") === "1"
  const reel = searchParams.get("reel")?.trim()
  if (reel) return { kind: "reel", id: reel, openComments }
  const achievement = searchParams.get("achievement")?.trim()
  if (achievement) return { kind: "achievement", id: achievement, openComments }
  const trade = searchParams.get("trade")?.trim()
  if (trade) return { kind: "trade", id: trade, openComments }
  const post = searchParams.get("post")?.trim()
  if (post) return { kind: "post", id: post, openComments }
  return null
}

export function feedDeepLinkSessionKey(target: FeedDeepLinkTarget): string {
  return `${target.kind}:${target.id}:${target.openComments ? "1" : "0"}`
}

const FEED_DEEP_LINK_PARAM: Record<FeedDeepLinkKind, string> = {
  post: "post",
  trade: "trade",
  achievement: "achievement",
  reel: "reel",
}

/** Canonical in-app path for a feed deep link (`/feed?post=…`, etc.). */
export function buildFeedDeepLinkHref(
  target: Pick<FeedDeepLinkTarget, "kind" | "id"> & {
    openComments?: boolean
  }
): string {
  const id = String(target.id ?? "").trim()
  if (!id) return "/feed"

  const params = new URLSearchParams()
  params.set(FEED_DEEP_LINK_PARAM[target.kind], id)
  if (target.openComments) params.set("comments", "1")
  return `/feed?${params.toString()}`
}

/** Absolute URL for Copy Link (uses `window.location.origin` when omitted). */
export function buildFeedDeepLinkAbsoluteUrl(
  target: Pick<FeedDeepLinkTarget, "kind" | "id"> & {
    openComments?: boolean
  },
  origin?: string
): string {
  const base =
    origin ??
    (typeof window !== "undefined" ? window.location.origin : "")
  return `${String(base).replace(/\/$/, "")}${buildFeedDeepLinkHref(target)}`
}

export type ShareContentFeedKind = "trade" | "profile" | "achievement" | "reel"

/** Map share modal / DM payload fields to a feed deep-link target. */
export function feedDeepLinkTargetFromShareInput(opts: {
  postId?: string | null
  tradeId?: string | null
  feedKind?: ShareContentFeedKind | null
}): Pick<FeedDeepLinkTarget, "kind" | "id"> | null {
  const tradeId = String(opts.tradeId ?? "").trim()
  if (tradeId) return { kind: "trade", id: tradeId }

  const postId = String(opts.postId ?? "").trim()
  if (!postId) return null

  if (opts.feedKind === "reel") return { kind: "reel", id: postId }
  if (opts.feedKind === "achievement") {
    return { kind: "achievement", id: postId }
  }
  return { kind: "post", id: postId }
}

export async function copyFeedDeepLinkToClipboard(
  target: Pick<FeedDeepLinkTarget, "kind" | "id"> & {
    openComments?: boolean
  }
): Promise<boolean> {
  if (typeof navigator === "undefined" || !navigator.clipboard?.writeText) {
    return false
  }
  try {
    await navigator.clipboard.writeText(buildFeedDeepLinkAbsoluteUrl(target))
    void import("@/lib/nativeHaptics").then(({ hapticLight }) => {
      hapticLight("clipboard")
    })
    return true
  } catch {
    return false
  }
}

/** Fetch one feed item by deep-link target — bypasses feed scope filters. */
export async function fetchFeedDeepLinkContent(
  supabase: SupabaseClient,
  target: Pick<FeedDeepLinkTarget, "kind" | "id">
): Promise<FeedItem | null> {
  switch (target.kind) {
    case "reel":
      return fetchReelFeedPostById(supabase, target.id)
    case "achievement":
      return fetchAchievementPostById(supabase, target.id)
    case "trade":
      return fetchTradeFeedPostByTradeId(supabase, target.id)
    case "post": {
      const tradePost = await fetchTradeFeedPostById(supabase, target.id)
      if (tradePost) return tradePost
      return fetchProfileFeedPostById(supabase, target.id)
    }
  }
}
