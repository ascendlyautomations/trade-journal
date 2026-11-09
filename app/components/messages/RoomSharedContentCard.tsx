"use client"

import { memo, useEffect, useState } from "react"
import FeedPostScreenshot from "@/app/components/feed/FeedPostScreenshot"
import SharedTradeMessageCard from "@/app/components/SharedTradeMessageCard"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import { ProfileUsernameLink } from "@/app/components/ProfileLink"
import { FEED_ACHIEVEMENT_POSTS_SELECT } from "@/lib/achievementPostEngagement"
import { formatRR, formatSignedPnlDisplay } from "@/lib/formatDisplay"
import { FEED_REELS_SELECT } from "@/lib/reelEngagement"
import {
  roomSharedContentLabel,
  type RoomSharedContentReference,
} from "@/lib/roomMessageSharedContent"
import {
  getCachedRoomSharedPostEmbed,
  getOrCreateRoomSharedPostInflight,
  setCachedRoomSharedPostEmbed,
  stableRoomSharedContentKey,
} from "@/lib/roomSharedContentEmbedCache"
import {
  getSharedContentViewHref,
  SHARED_POST_UNAVAILABLE,
} from "@/lib/sharedContentNavigation"
import { profilePostPublicUrl } from "@/lib/storagePublicUrl"
import { supabase } from "@/lib/supabaseClient"

function postScreenshotSrc(url: string | null | undefined): string | null {
  const raw = url != null ? String(url).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

type RoomSharedContentCardProps = {
  reference: RoomSharedContentReference
  viewerUserId?: string | null
  onViewTrade: (trade: { id?: string | null }) => void
  onNavigate: (href: string) => void
  deferUntilVisible?: boolean
  className?: string
}

function RoomSharedContentCard({
  reference,
  viewerUserId,
  onViewTrade,
  onNavigate,
  deferUntilVisible = true,
  className,
}: RoomSharedContentCardProps) {
  if (reference.kind === "trade" && reference.tradeId) {
    return (
      <SharedTradeMessageCard
        tradeId={reference.tradeId}
        viewerUserId={viewerUserId}
        onViewTrade={onViewTrade}
        deferUntilVisible={deferUntilVisible}
        optimizeMessagePreview
        className={className}
      />
    )
  }

  return (
    <RoomSharedPostLikeCard
      reference={reference}
      onNavigate={onNavigate}
      className={className}
    />
  )
}

const RoomSharedContentCardMemo = memo(RoomSharedContentCard, (prev, next) => {
  if (stableRoomSharedContentKey(prev.reference) !== stableRoomSharedContentKey(next.reference)) {
    return false
  }
  return (
    prev.viewerUserId === next.viewerUserId &&
    prev.deferUntilVisible === next.deferUntilVisible &&
    prev.className === next.className &&
    prev.onViewTrade === next.onViewTrade &&
    prev.onNavigate === next.onNavigate
  )
})

RoomSharedContentCardMemo.displayName = "RoomSharedContentCard"

export default RoomSharedContentCardMemo

function RoomSharedPostLikeCard({
  reference,
  onNavigate,
  className,
}: {
  reference: RoomSharedContentReference
  onNavigate: (href: string) => void
  className?: string
}) {
  const embedKey = stableRoomSharedContentKey(reference)
  const initialCached = getCachedRoomSharedPostEmbed(embedKey)
  const [post, setPost] = useState<unknown | null>(() =>
    initialCached !== undefined ? initialCached : null
  )
  const [loading, setLoading] = useState(() => initialCached === undefined)
  const [lightboxImageUrl, setLightboxImageUrl] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    const key = embedKey

    const cached = getCachedRoomSharedPostEmbed(key)
    if (cached !== undefined) {
      setPost(cached)
      setLoading(false)
      return () => {
        cancelled = true
      }
    }

    setLoading(true)
    setPost(null)

    /**
     * Apply state from the shared inflight promise, not only from inside the factory.
     * In React Strict Mode the effect runs twice: the first run sets `cancelled` before the
     * factory resolves, so `if (!cancelled)` inside the factory skips setState forever while
     * the second run reuses the same promise and must still hydrate the UI (cache may fill
     * after the aborted run's cleanup).
     */
    const inflight = getOrCreateRoomSharedPostInflight(key, async () => {
      let row: unknown = null

      if (reference.kind === "reel" && reference.reelId) {
        const { data } = await supabase
          .from("reels")
          .select(FEED_REELS_SELECT)
          .eq("id", reference.reelId)
          .maybeSingle()
        row = data ? { ...data, feedKind: "reel" as const } : null
      } else if (reference.kind === "achievement_post" && reference.achievementPostId) {
        const { data } = await supabase
          .from("achievement_posts")
          .select(FEED_ACHIEVEMENT_POSTS_SELECT)
          .eq("id", reference.achievementPostId)
          .maybeSingle()
        row = data ?? null
      } else if (reference.kind === "profile_post" && reference.profilePostId) {
        const { data } = await supabase
          .from("profile_posts")
          .select("*, profiles(username, avatar_url)")
          .eq("id", reference.profilePostId)
          .maybeSingle()
        row = data ?? null
      } else if (reference.kind === "post" && reference.postId) {
        const { data } = await supabase
          .from("posts")
          .select("*, profiles(username, avatar_url)")
          .eq("id", reference.postId)
          .maybeSingle()
        row = data ?? null
      }

      setCachedRoomSharedPostEmbed(key, row)
      return row
    })

    void inflight.then((row) => {
      if (cancelled) return
      setPost(row ?? null)
      setLoading(false)
    })

    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- embedKey encodes kind + id; `reference` is unstable identity from parent
  }, [embedKey])

  const shellClass =
    className ??
    "w-full min-w-[15rem] max-w-[min(100%,19.5rem)] overflow-hidden rounded-xl border border-white/10 bg-white/5 shadow-lg shadow-black/20"

  if (loading) {
    return (
      <div className={`${shellClass} p-3 text-sm text-gray-300`}>
        Loading…
      </div>
    )
  }

  if (!post) {
    return (
      <div className={`${shellClass} p-3 text-sm italic text-gray-300`}>
        {SHARED_POST_UNAVAILABLE}
      </div>
    )
  }

  const postRow = post as Record<string, unknown>
  const isReel = reference.kind === "reel"
  const isAchievement = reference.kind === "achievement_post"
  const isProfile = reference.kind === "profile_post"
  const imageSrc = isReel
    ? postRow.thumbnail_url != null
      ? String(postRow.thumbnail_url)
      : null
    : isProfile
      ? profilePostPublicUrl(postRow.image_url as string | null | undefined)
      : postScreenshotSrc(postRow.image_url as string | null | undefined)
  const pnl = Number(postRow.pnl)
  const isWin = !Number.isNaN(pnl) && pnl >= 0
  const showTradeStats =
    reference.kind === "post" && !Number.isNaN(pnl)
  const achievementTitle = isAchievement
    ? String(
        (postRow.achievements as { title?: string } | undefined)?.title ??
          "Achievement"
      )
    : null
  const reelCaption =
    isReel && postRow.caption != null ? String(postRow.caption).trim() : ""
  const shareLabel = roomSharedContentLabel(reference.kind)
  const viewLabel = isReel
    ? "clip"
    : isAchievement
      ? "achievement"
      : "post"

  return (
    <>
      <div className={shellClass}>
        <div className="p-3">
          <div className="mb-2 flex items-center justify-between gap-3">
            <ProfileUsernameLink
              userId={String(
                postRow.user_id ??
                  (postRow.profiles as { id?: string } | undefined)?.id ??
                  ""
              )}
              username={
                (postRow.profiles as { username?: string } | undefined)?.username
              }
              stopPropagation
              className="text-sm font-semibold text-white hover:underline"
            >
              @
              {(postRow.profiles as { username?: string } | undefined)?.username ||
                "User"}
            </ProfileUsernameLink>
            <span className="shrink-0 text-xs text-gray-400">{shareLabel}</span>
          </div>

          {isAchievement ? (
            <p className="mb-2 text-sm font-medium text-amber-200">
              🏆 {achievementTitle}
            </p>
          ) : null}

          {imageSrc ? (
            <FeedPostScreenshot
              imageSrc={imageSrc}
              variant="message"
              wrapperClassName="mb-2 w-full overflow-hidden rounded-lg border border-white/10 bg-white/5"
              onImageClick={setLightboxImageUrl}
            />
          ) : null}

          {postRow.content ? (
            <p className="mb-2 whitespace-pre-wrap break-words text-sm leading-relaxed text-gray-200">
              {String(postRow.content)}
            </p>
          ) : null}

          {reelCaption ? (
            <p className="mb-2 whitespace-pre-wrap break-words text-sm leading-relaxed text-gray-200">
              {reelCaption}
            </p>
          ) : null}

          {showTradeStats ? (
            <div className="mb-2 flex justify-between text-xs">
              <span className={isWin ? "text-green-400" : "text-red-400"}>
                {formatSignedPnlDisplay(pnl)}
              </span>
              <span className="text-gray-400">
                RR {formatRR(postRow.rr as string | number | null | undefined)}
              </span>
            </div>
          ) : null}

          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onNavigate(
                getSharedContentViewHref(
                  postRow as unknown as Parameters<
                    typeof getSharedContentViewHref
                  >[0]
                )
              )
            }}
            className="w-full rounded-lg border border-blue-500/30 bg-blue-500/10 px-3 py-2 text-xs font-medium text-blue-300 transition hover:bg-blue-500/20 hover:text-blue-200"
          >
            View {viewLabel} →
          </button>
        </div>
      </div>

      <ImageLightbox
        open={lightboxImageUrl != null}
        imageUrl={lightboxImageUrl}
        onClose={() => setLightboxImageUrl(null)}
      />
    </>
  )
}
