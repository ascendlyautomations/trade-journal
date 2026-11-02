"use client"

import Link from "next/link"
import {
  useCallback,
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type UIEvent,
} from "react"
import {
  Heart,
  MessageCircle,
  MoreHorizontal,
  Share2,
  Volume2,
  VolumeX,
} from "lucide-react"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import FeedPostModerationMenu from "@/app/components/feed/FeedPostModerationMenu"
import FeedReelOwnerMenu from "@/app/components/feed/FeedReelOwnerMenu"
import LinkedTradeBadge from "@/app/components/feed/LinkedTradeBadge"
import type { FeedLikeMeta } from "@/app/components/feed/FeedPostCard"
import {
  isTradeAttachedReel,
  resolveReelCaption,
} from "@/lib/reels"
import { getReelPosterImageUrl } from "@/lib/reelVideo"
import MobileWebOpenInAppLink from "@/app/components/mobile/MobileWebOpenInAppLink"
import { mobileWebOpenInAppContentLink } from "@/lib/mobileWebOpenInApp"
import { profilePath } from "@/lib/profileRoutes"
import {
  formatMobileWebClipCount,
  readMobileWebClipsPostId,
  writeMobileWebClipsPostId,
} from "@/lib/mobileWebClips"

type MobileWebClipsPagerProps = {
  posts: any[]
  user: any
  likesByPost: Record<string, FeedLikeMeta>
  likeBusyByPost?: Record<string, boolean>
  commentCountsByPost: Record<string, number>
  followingIds: readonly string[]
  onToggleLike: (post: any) => void
  onOpenComments: (post: any) => void
  onSharePost: (post: any) => void
  onOpenLinkedTrade?: (post: any) => void
  onFollow?: (userId: string) => void
  onLoadMore?: () => void
  hasMore?: boolean
  loadingMore?: boolean
  canManageReel?: (post: any) => boolean
  openReelMenuId?: string | null
  onReelMenuToggle?: (reelId: string) => void
  onEditReel?: (post: any) => void
  onDeleteReel?: (post: any) => void
  onReplaceReelVideo?: (post: any) => void
  initialReelId?: string | null
}

export default function MobileWebClipsPager({
  posts,
  user,
  likesByPost,
  likeBusyByPost = {},
  commentCountsByPost,
  followingIds,
  onToggleLike,
  onOpenComments,
  onSharePost,
  onOpenLinkedTrade,
  onFollow,
  onLoadMore,
  hasMore = false,
  loadingMore = false,
  canManageReel,
  openReelMenuId = null,
  onReelMenuToggle,
  onEditReel,
  onDeleteReel,
  onReplaceReelVideo,
  initialReelId = null,
}: MobileWebClipsPagerProps) {
  const scrollerRef = useRef<HTMLDivElement | null>(null)
  const [activeIndex, setActiveIndex] = useState(0)
  const [muted, setMuted] = useState(true)
  const didSeekInitial = useRef(false)
  const didRestoreScroll = useRef(false)
  const skipPersist = useRef(false)

  useEffect(() => {
    if (didSeekInitial.current || !initialReelId || posts.length === 0) return
    const index = posts.findIndex((post) => String(post.id) === String(initialReelId))
    if (index < 0) return
    didSeekInitial.current = true
    setActiveIndex(index)
    const scroller = scrollerRef.current
    const page = scroller?.children[index] as HTMLElement | undefined
    page?.scrollIntoView({ block: "start" })
  }, [initialReelId, posts])

  useEffect(() => {
    if (posts.length === 0 || didRestoreScroll.current) return
    if (initialReelId) {
      didRestoreScroll.current = true
      return
    }
    const saved = readMobileWebClipsPostId()
    if (!saved) {
      didRestoreScroll.current = true
      return
    }
    const index = posts.findIndex((post) => String(post.id) === saved)
    if (index < 0) return
    didRestoreScroll.current = true
    if (index === 0) return
    skipPersist.current = true
    const scroller = scrollerRef.current
    if (!scroller) return
    setActiveIndex(index)
    const apply = () => {
      const height = scroller.clientHeight
      if (height > 0) {
        scroller.scrollTo({ top: index * height, behavior: "auto" })
      }
    }
    apply()
    requestAnimationFrame(apply)
  }, [initialReelId, posts])

  useEffect(() => {
    if (!didRestoreScroll.current) return
    if (skipPersist.current) {
      skipPersist.current = false
      return
    }
    const post = posts[activeIndex]
    if (!post) return
    writeMobileWebClipsPostId(String(post.id))
  }, [activeIndex, posts])

  const updateActiveFromScroll = useCallback(() => {
    const root = scrollerRef.current
    if (!root) return
    const height = root.clientHeight || 1
    const next = Math.round(root.scrollTop / height)
    const clamped = Math.max(0, Math.min(posts.length - 1, next))
    setActiveIndex((prev) => (prev === clamped ? prev : clamped))
  }, [posts.length])

  function handleScroll(event: UIEvent<HTMLDivElement>) {
    updateActiveFromScroll()
    const target = event.currentTarget
    if (
      hasMore &&
      onLoadMore &&
      target.scrollTop + target.clientHeight >= target.scrollHeight - target.clientHeight * 1.5
    ) {
      onLoadMore()
    }
  }

  if (posts.length === 0) return null

  return (
    <div className="relative h-full min-h-0">
    <div
      ref={scrollerRef}
      onScroll={handleScroll}
      className="h-full snap-y snap-mandatory overflow-x-hidden overflow-y-scroll overscroll-y-contain [scrollbar-width:none] [-ms-overflow-style:none] [&::-webkit-scrollbar]:hidden motion-reduce:snap-none motion-reduce:scroll-auto"
      data-tt-mobile-web-clips-pager
      aria-label="Clips"
    >
      {posts.map((post, index) => (
        <MobileWebClipPage
          key={String(post.id)}
          post={post}
          user={user}
          active={index === activeIndex}
          nearActive={Math.abs(index - activeIndex) <= 1}
          muted={muted}
          likeMeta={likesByPost[String(post.id)] ?? { count: 0, liked: false }}
          likeBusy={!!likeBusyByPost[String(post.id)]}
          commentCount={commentCountsByPost[String(post.id)] ?? 0}
          isFollowing={followingIds.includes(String(post.user_id))}
          onToggleLike={onToggleLike}
          onOpenComments={onOpenComments}
          onSharePost={onSharePost}
          onOpenLinkedTrade={onOpenLinkedTrade}
          onFollow={onFollow}
          onToggleMute={() => setMuted((prev) => !prev)}
          canManage={canManageReel?.(post) ?? false}
          menuOpen={openReelMenuId === String(post.id)}
          onMenuToggle={onReelMenuToggle}
          onEditReel={onEditReel}
          onDeleteReel={onDeleteReel}
          onReplaceReelVideo={onReplaceReelVideo}
        />
      ))}
    </div>
      {loadingMore ? (
        <div className="pointer-events-none absolute inset-x-0 bottom-24 z-10 flex justify-center">
          <span className="rounded-full bg-black/55 px-3 py-1 text-sm text-white/80">
            Loading more clips…
          </span>
        </div>
      ) : null}
    </div>
  )
}

function MobileWebClipPage({
  post,
  user,
  active,
  nearActive,
  muted,
  likeMeta,
  likeBusy,
  commentCount,
  isFollowing,
  onToggleLike,
  onOpenComments,
  onSharePost,
  onOpenLinkedTrade,
  onFollow,
  onToggleMute,
  canManage,
  menuOpen,
  onMenuToggle,
  onEditReel,
  onDeleteReel,
  onReplaceReelVideo,
}: {
  post: any
  user: any
  active: boolean
  nearActive: boolean
  muted: boolean
  likeMeta: FeedLikeMeta
  likeBusy: boolean
  commentCount: number
  isFollowing: boolean
  onToggleLike: (post: any) => void
  onOpenComments: (post: any) => void
  onSharePost: (post: any) => void
  onOpenLinkedTrade?: (post: any) => void
  onFollow?: (userId: string) => void
  onToggleMute: () => void
  canManage: boolean
  menuOpen: boolean
  onMenuToggle?: (reelId: string) => void
  onEditReel?: (post: any) => void
  onDeleteReel?: (post: any) => void
  onReplaceReelVideo?: (post: any) => void
}) {
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const [paused, setPaused] = useState(false)
  const [videoFailed, setVideoFailed] = useState(false)
  const videoUrl = String(post.video_url ?? "").trim()
  const poster = getReelPosterImageUrl(post.thumbnail_url) ?? undefined
  const caption = resolveReelCaption(post)
  const username = post.profiles?.username || "User"
  const avatarUrl = post.profiles?.avatar_url ?? null
  const authorId = String(post.user_id ?? "")
  const isOwner = Boolean(user?.id && authorId && String(user.id) === authorId)
  const showFollow = Boolean(onFollow && user?.id && !isOwner && !isFollowing && authorId)
  const tradeAttached = isTradeAttachedReel(post)

  useEffect(() => {
    const video = videoRef.current
    if (!video) return
    if (!active) {
      video.pause()
      return
    }
    if (paused) {
      video.pause()
      return
    }
    const play = () => {
      void video.play().catch(() => {})
    }
    play()
    return () => {
      video.pause()
    }
  }, [active, paused, videoUrl])

  useEffect(() => {
    if (active) setPaused(false)
    setVideoFailed(false)
  }, [active, post.id])

  function handleTapMedia() {
    if (videoFailed) {
      setVideoFailed(false)
      setPaused(false)
      return
    }
    setPaused((prev) => !prev)
  }

  return (
    <section
      className="relative h-full w-full shrink-0 snap-start snap-always overflow-hidden bg-black"
      aria-label={`Clip by ${username}`}
    >
      {active && videoUrl && !videoFailed ? (
        <video
          ref={videoRef}
          src={videoUrl}
          poster={poster}
          className="absolute inset-0 h-full w-full object-cover"
          playsInline
          loop
          muted={muted}
          preload="auto"
          disablePictureInPicture
          onError={() => setVideoFailed(true)}
          onClick={handleTapMedia}
        />
      ) : poster ? (
        <img
          src={poster}
          alt=""
          loading={nearActive ? "eager" : "lazy"}
          decoding="async"
          className="absolute inset-0 h-full w-full object-cover"
        />
      ) : (
        <div className="absolute inset-0 bg-black" aria-hidden />
      )}

      {(paused || videoFailed) && active ? (
        <button
          type="button"
          onClick={handleTapMedia}
          className="absolute inset-0 z-[1] flex items-center justify-center"
          aria-label="Play clip"
        >
          <span className="flex h-16 w-16 items-center justify-center rounded-full bg-black/35 text-white">
            <svg viewBox="0 0 24 24" className="h-8 w-8 translate-x-0.5" fill="currentColor" aria-hidden>
              <path d="M8 5.14v13.72a1 1 0 0 0 1.5.86l11.04-6.86a1 1 0 0 0 0-1.72L9.5 4.28A1 1 0 0 0 8 5.14z" />
            </svg>
          </span>
        </button>
      ) : (
        <button
          type="button"
          onClick={handleTapMedia}
          className="absolute inset-0 z-[1] pr-[72px]"
          aria-label={paused || videoFailed ? "Play clip" : "Pause clip"}
        />
      )}

      {active ? (
        <div className="absolute right-3 top-[calc(env(safe-area-inset-top,0px)+4.75rem)] z-[5]">
          <MobileWebOpenInAppLink
            link={mobileWebOpenInAppContentLink("clip", String(post.id ?? ""))}
            variant="overlay"
          />
        </div>
      ) : null}

      <div className="pointer-events-none absolute inset-x-0 bottom-0 z-[2] h-[280px] bg-gradient-to-t from-black/70 via-black/25 to-transparent" />

      <div className="absolute inset-x-0 bottom-0 z-[3] flex items-end gap-3 px-4 pb-[max(15px,env(safe-area-inset-bottom))]">
        <div className="min-w-0 flex-1 pb-1">
          <div className="flex items-center gap-2">
            <Link
              href={profilePath({ id: authorId, username })}
              className="flex min-w-0 items-center gap-2"
              onClick={(event) => event.stopPropagation()}
            >
              <ProfileAvatarImg src={avatarUrl} className="h-8 w-8" />
              <span className="truncate text-[15px] font-semibold text-white drop-shadow">
                {username}
              </span>
            </Link>
            {showFollow ? (
              <button
                type="button"
                onClick={(event) => {
                  event.stopPropagation()
                  onFollow?.(authorId)
                }}
                className="tt-mobile-web-hit-slop relative inline-flex h-7 min-w-11 items-center justify-center rounded-full border border-white/80 bg-white/20 px-2.5 text-[12px] font-bold text-white"
              >
                Follow
              </button>
            ) : null}
          </div>
          {caption ? (
            <p className="mt-2 line-clamp-2 text-[13px] leading-snug text-white/95 drop-shadow">
              {caption}
            </p>
          ) : null}
          {tradeAttached && onOpenLinkedTrade ? (
            <div className="mt-2">
              <LinkedTradeBadge
                onClick={(event) => {
                  event.stopPropagation()
                  onOpenLinkedTrade(post)
                }}
              />
            </div>
          ) : null}
        </div>

        <div className="flex w-[52px] shrink-0 flex-col items-center gap-[18px] pb-1">
          <ClipRailButton
            label={likeMeta.liked ? "Unlike" : "Like"}
            value={formatMobileWebClipCount(likeMeta.count)}
            disabled={likeBusy}
            onClick={() => onToggleLike(post)}
          >
            <Heart
              className={`h-7 w-7 ${likeMeta.liked ? "fill-red-500 text-red-500" : "text-white"}`}
              strokeWidth={1.8}
            />
          </ClipRailButton>
          <ClipRailButton
            label="Comments"
            value={formatMobileWebClipCount(commentCount)}
            onClick={() => onOpenComments(post)}
          >
            <MessageCircle className="h-7 w-7 text-white" strokeWidth={1.8} />
          </ClipRailButton>
          <ClipRailButton label="Share" onClick={() => onSharePost(post)}>
            <Share2 className="h-7 w-7 text-white" strokeWidth={1.8} />
          </ClipRailButton>
          <ClipRailButton
            label={muted ? "Unmute" : "Mute"}
            onClick={onToggleMute}
          >
            {muted ? (
              <VolumeX className="h-7 w-7 text-white" strokeWidth={1.8} />
            ) : (
              <Volume2 className="h-7 w-7 text-white" strokeWidth={1.8} />
            )}
          </ClipRailButton>
          {canManage ? (
            <div className="text-white [&_button]:text-white [&_.absolute]:bottom-full [&_.absolute]:mb-2 [&_.absolute]:right-0 [&_.absolute]:mt-0">
              <FeedReelOwnerMenu
                menuOpen={menuOpen}
                onMenuToggle={() => onMenuToggle?.(String(post.id))}
                onEdit={() => onEditReel?.(post)}
                onDelete={() => onDeleteReel?.(post)}
                onReplaceVideo={() => onReplaceReelVideo?.(post)}
                isTradeAttached={tradeAttached}
              />
            </div>
          ) : (
            <div className="text-white">
              <FeedPostModerationMenu post={post} viewerUserId={user?.id} />
              <span className="sr-only">More</span>
              <MoreHorizontal className="hidden" />
            </div>
          )}
        </div>
      </div>
    </section>
  )
}

function ClipRailButton({
  label,
  value,
  disabled,
  onClick,
  children,
}: {
  label: string
  value?: string | null
  disabled?: boolean
  onClick: () => void
  children: ReactNode
}) {
  return (
    <button
      type="button"
      aria-label={label}
      disabled={disabled}
      onClick={(event) => {
        event.stopPropagation()
        onClick()
      }}
      className="flex min-h-11 w-11 flex-col items-center justify-center text-white disabled:opacity-60"
    >
      {children}
      {value ? (
        <span className="mt-0.5 text-[11px] font-semibold tabular-nums drop-shadow">
          {value}
        </span>
      ) : null}
    </button>
  )
}
