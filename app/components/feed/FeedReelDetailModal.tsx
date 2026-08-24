"use client"

import dynamic from "next/dynamic"
import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react"
import DetailModalShell, {
  scrollModalCommentsPane,
} from "@/app/components/ui/DetailModalShell"
import DetailModalVideo from "@/app/components/ui/DetailModalVideo"
import type { ReelClipPlaybackHandle } from "@/app/components/ReelClipPlayback"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostHeader from "./FeedPostHeader"
import FeedPostMetaRow from "./FeedPostMetaRow"
import FeedReelOwnerMenu from "./FeedReelOwnerMenu"
import TradeReelSummaryStrip from "./TradeReelSummaryStrip"
import { feedCommentTarget } from "./feedPostHelpers"
import { resolveReelCaption } from "@/lib/reels"
import type { FeedLikeMeta } from "./FeedPostCard"
import { DETAIL_MODAL_STACKED_Z_INDEX_CLASS } from "@/app/components/ui/modalLayout"
import { useIsNativeIos } from "@/lib/useIsNativeIos"

const NativeIosMediaViewer = dynamic(
  () => import("@/app/components/ui/NativeIosMediaViewer"),
  { ssr: false }
)

type FeedReelDetailModalProps = {
  post: any
  user: any
  comments: any[]
  commentCount: number
  likeMeta: FeedLikeMeta
  likeBusy?: boolean
  commentSubmitting: boolean
  draftSyncRef: MutableRefObject<Record<string, string>>
  openCommentsRef: MutableRefObject<Record<string, boolean>>
  openTradeRef?: MutableRefObject<Record<string, boolean>>
  tradeExpandSignal?: number
  onClose: () => void
  onToggleLike: (post: any) => void
  onSubmitComment: (
    post: any,
    text: string,
    parentCommentId?: string | null,
    retryTempId?: string | null
  ) => Promise<boolean>
  onDeleteComment?: (comment: any) => Promise<boolean>
  onTogglePinComment?: (comment: any, pinned: boolean) => Promise<boolean>
  onSharePost: (post: any) => void
  canManageReel?: boolean
  menuOpen?: boolean
  onMenuToggle?: () => void
  onEditReel?: () => void
  onDeleteReel?: () => void
  onReplaceReelVideo?: () => void
  isTradeAttachedReel?: boolean
  /**
   * When opened above another detail modal (e.g. View Clip from Trade Details),
   * use the stacked z-index so this shell sits on top without unmounting the parent.
   */
  stacked?: boolean
}

export default function FeedReelDetailModal({
  post,
  user,
  comments,
  commentCount,
  likeMeta,
  likeBusy = false,
  commentSubmitting,
  draftSyncRef,
  openCommentsRef,
  openTradeRef,
  tradeExpandSignal = 0,
  onClose,
  onToggleLike,
  onSubmitComment,
  onDeleteComment,
  onTogglePinComment,
  onSharePost,
  canManageReel = false,
  menuOpen = false,
  onMenuToggle,
  onEditReel,
  onDeleteReel,
  onReplaceReelVideo,
  isTradeAttachedReel = false,
  stacked = false,
}: FeedReelDetailModalProps) {
  const nativeIos = useIsNativeIos()
  const pid = String(post.id)
  const playbackRef = useRef<ReelClipPlaybackHandle>(null)
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const [commentsFocused, setCommentsFocused] = useState(
    () => Boolean(openCommentsRef.current[pid])
  )
  const [nativeFullscreen, setNativeFullscreen] = useState(false)
  const [nativeStartTime, setNativeStartTime] = useState(0)

  const commentTarget = useMemo(
    () => feedCommentTarget(pid, post),
    [pid, post]
  )

  const scrollCommentsIntoView = useCallback(() => {
    requestAnimationFrame(() => {
      scrollModalCommentsPane(commentsScrollRef.current)
    })
  }, [])

  const focusComments = useCallback(() => {
    setCommentsFocused(true)
    scrollCommentsIntoView()
  }, [scrollCommentsIntoView])

  useEffect(() => {
    if (openCommentsRef.current[pid]) {
      setCommentsFocused(true)
      scrollCommentsIntoView()
      openCommentsRef.current[pid] = false
    }
  }, [openCommentsRef, pid, scrollCommentsIntoView])

  useEffect(() => {
    if (!openTradeRef?.current[pid] && tradeExpandSignal === 0) return
    setCommentsFocused(false)
  }, [openTradeRef, pid, tradeExpandSignal])

  useEffect(() => {
    const playback = playbackRef
    return () => {
      const video = playback.current?.getVideoElement()
      if (video) {
        video.pause()
        video.removeAttribute("src")
        video.load()
      }
      playback.current?.pause()
    }
  }, [pid])

  const modalDetails = useMemo(() => {
    const rawAvatar = post.profiles?.avatar_url
    const avatarUrl =
      rawAvatar != null && String(rawAvatar).trim() !== ""
        ? String(rawAvatar).trim()
        : null
    const caption = resolveReelCaption(post)

    return {
      avatarUrl,
      username: post.profiles?.username || "User",
      caption,
    }
  }, [post])

  const openNativeFullscreen = useCallback(() => {
    if (!nativeIos) return
    const video = playbackRef.current?.getVideoElement()
    const time = video?.currentTime ?? 0
    playbackRef.current?.pause()
    setNativeStartTime(time)
    setNativeFullscreen(true)
  }, [nativeIos])

  const closeNativeFullscreen = useCallback(() => {
    setNativeFullscreen(false)
  }, [])

  const restoreInlineTime = useCallback(
    (_url: string, time: number) => {
      const video = playbackRef.current?.getVideoElement()
      if (!video || !Number.isFinite(time)) return
      try {
        video.currentTime = time
      } catch {
        // Seek may fail if element was recycled.
      }
    },
    []
  )

  const splitMedia = (
    <div
      className={nativeIos ? "relative" : undefined}
      onClick={
        nativeIos
          ? (e) => {
              e.preventDefault()
              e.stopPropagation()
              openNativeFullscreen()
            }
          : undefined
      }
      role={nativeIos ? "button" : undefined}
      tabIndex={nativeIos ? 0 : undefined}
      aria-label={nativeIos ? "Open fullscreen video" : undefined}
      onKeyDown={
        nativeIos
          ? (e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault()
                openNativeFullscreen()
              }
            }
          : undefined
      }
    >
      <div className={nativeIos ? "pointer-events-none" : undefined}>
        <DetailModalVideo
          ref={playbackRef}
          src={String(post.video_url)}
          poster={String(post.thumbnail_url)}
        />
      </div>
    </div>
  )

  const splitPanel = (
    <MobileCommentFocusLayout
      commentsFocused={commentsFocused}
      header={
        <div className="flex items-center border-b border-white/5">
          <div className="min-w-0 flex-1">
            <FeedPostHeader
              userId={post.user_id}
              avatarUrl={modalDetails.avatarUrl}
              username={modalDetails.username}
              metaLabel="Clip"
              metaLabelClassName="font-medium text-violet-400/90"
              postedAt={post.created_at}
            />
          </div>
          {canManageReel ? (
            <div className="pr-3">
              <FeedReelOwnerMenu
                menuOpen={menuOpen}
                onMenuToggle={() => onMenuToggle?.()}
                onEdit={() => onEditReel?.()}
                onDelete={() => onDeleteReel?.()}
                onReplaceVideo={() => onReplaceReelVideo?.()}
                isTradeAttached={isTradeAttachedReel}
              />
            </div>
          ) : null}
        </div>
      }
      compactHeader={
        <CommentFocusCompactStrip
          userId={String(post.user_id ?? "")}
          username={modalDetails.username}
          avatarUrl={modalDetails.avatarUrl}
          meta={
            <FeedPostMetaRow
              label="Clip"
              labelClassName="font-medium text-violet-400/90"
              createdAt={post.created_at}
            />
          }
          onExpand={() => setCommentsFocused(false)}
        />
      }
      engagement={
        <PostInteractionsEngagement
          post={post}
          user={user}
          comments={comments}
          commentCount={commentCount}
          likeMeta={likeMeta}
          likeBusy={likeBusy}
          onToggleLike={onToggleLike}
          onOpenComments={() => focusComments()}
          onSharePost={onSharePost}
        />
      }
      engagementClassName="shrink-0 border-b border-white/10 px-4 py-2"
      collapsibleContent={
        <div className="space-y-3 border-b border-white/10 px-4 py-4 text-sm">
          <TradeReelSummaryStrip
            post={post}
            viewerUserId={user?.id ?? null}
            openTradeRef={openTradeRef}
            tradeExpandSignal={tradeExpandSignal}
          />
          {modalDetails.caption ? (
            <p className="whitespace-pre-wrap leading-relaxed text-white">
              {modalDetails.caption}
            </p>
          ) : null}
        </div>
      }
      comments={
        <FeedCommentsSection
          target={commentTarget}
          user={user}
          comments={comments}
          commentSubmitting={commentSubmitting}
          draftSyncRef={draftSyncRef}
          listScrollRef={commentsScrollRef}
          onSubmitComment={(context, text, parentCommentId, retryTempId) =>
            onSubmitComment(context, text, parentCommentId, retryTempId)
          }
          onDeleteComment={onDeleteComment}
          onTogglePinComment={onTogglePinComment}
        />
      }
    />
  )

  return (
    <>
      <DetailModalShell
        ariaLabel="Clip details"
        title="Clip"
        layout="split"
        onClose={onClose}
        splitMedia={splitMedia}
        splitPanel={splitPanel}
        suppressMobileSplitMedia={commentsFocused}
        zIndexClass={
          stacked ? DETAIL_MODAL_STACKED_Z_INDEX_CLASS : undefined
        }
      />
      {nativeIos && nativeFullscreen ? (
        <NativeIosMediaViewer
          open
          items={[
            {
              type: "video",
              url: String(post.video_url),
              poster: String(post.thumbnail_url ?? ""),
              initialTime: nativeStartTime,
              startMuted: true,
            },
          ]}
          onClose={closeNativeFullscreen}
          zIndexClass={DETAIL_MODAL_STACKED_Z_INDEX_CLASS}
          onVideoTime={restoreInlineTime}
        />
      ) : null}
    </>
  )
}
