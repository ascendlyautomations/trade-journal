"use client"

import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react"
import DetailModalShell, {
  scrollModalCommentsPane,
} from "@/app/components/ui/DetailModalShell"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"
import ExpandableText from "@/app/components/ui/ExpandableText"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import {
  formatPoints,
  formatRR,
  formatSignedPnlDisplay,
} from "@/lib/formatDisplay"
import { resolveTradePoints } from "@/lib/resolveTradePoints"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostHeader from "./FeedPostHeader"
import FeedPostMetaRow from "./FeedPostMetaRow"
import {
  feedCommentTarget,
  getModeStyles,
  postAttachedReel,
  postImageSrc,
  postPublicDescription,
  postTradeJoin,
} from "./feedPostHelpers"
import type { ReelRow } from "@/lib/reels"
import { formatPublicAccountTypeLabel } from "@/lib/publicAccountPrivacy"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedPostDetailModalProps = {
  post: any
  user: any
  comments: any[]
  commentCount: number
  likeMeta: FeedLikeMeta
  likeBusy?: boolean
  commentSubmitting: boolean
  draftSyncRef: MutableRefObject<Record<string, string>>
  openCommentsRef: MutableRefObject<Record<string, boolean>>
  onClose: () => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onDeleteComment?: (comment: any) => Promise<boolean>
  onTogglePinComment?: (comment: any, pinned: boolean) => Promise<boolean>
  onSharePost: (post: any) => void
  onOpenAttachedReel?: (post: any, reel: ReelRow) => void
}

export default function FeedPostDetailModal({
  post,
  user,
  comments,
  commentCount,
  likeMeta,
  likeBusy = false,
  commentSubmitting,
  draftSyncRef,
  openCommentsRef,
  onClose,
  onToggleLike,
  onSubmitComment,
  onDeleteComment,
  onTogglePinComment,
  onSharePost,
  onOpenAttachedReel,
}: FeedPostDetailModalProps) {
  const pid = String(post.id)
  const commentsScrollRef = useRef<HTMLDivElement>(null)
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)
  const [commentsFocused, setCommentsFocused] = useState(
    () => Boolean(openCommentsRef.current[pid])
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

  const modalPostDetails = useMemo(() => {
    const tradeJoin = postTradeJoin(post)
    const pnl = Number(post.pnl)
    const rawAvatar = post.profiles?.avatar_url
    const avatarUrl =
      rawAvatar != null && String(rawAvatar).trim() !== ""
        ? String(rawAvatar).trim()
        : null
    return {
      imageSrc: postImageSrc(post.image_url),
      publicDesc: postPublicDescription(post),
      ticker: tradeJoin?.ticker != null ? String(tradeJoin.ticker) : "—",
      dir: tradeJoin?.direction != null ? String(tradeJoin.direction) : "—",
      acctNorm: (() => {
        const raw = String(tradeJoin?.account_type ?? "").trim().toLowerCase()
        return formatPublicAccountTypeLabel(raw) ?? raw
      })(),
      acctStyleKey: String(tradeJoin?.account_type ?? "").trim().toLowerCase(),
      pnl,
      pnlPositive: !Number.isNaN(pnl) && pnl >= 0,
      points: resolveTradePoints(tradeJoin),
      timingTrade: tradeJoin,
      postedAt: post.created_at,
      avatarUrl,
      username: post.profiles?.username || "User",
    }
  }, [post])

  const attachedReel = useMemo(() => postAttachedReel(post), [post])

  const pnlMeta = (
    <>
      <span
        className={
          modalPostDetails.pnlPositive ? "text-emerald-400" : "text-red-400"
        }
      >
        {formatSignedPnlDisplay(modalPostDetails.pnl)}
      </span>
      <span className="text-gray-400"> · </span>
      <span>
        {modalPostDetails.ticker} • {modalPostDetails.dir}
      </span>
    </>
  )

  const splitMedia =
    modalPostDetails.imageSrc != null ? (
      <DetailModalImage
        src={modalPostDetails.imageSrc}
        onClick={setLightboxUrl}
      />
    ) : null

  const splitPanel = (
    <MobileCommentFocusLayout
      commentsFocused={commentsFocused}
      header={
        <FeedPostHeader
          userId={post.user_id}
          avatarUrl={modalPostDetails.avatarUrl}
          username={modalPostDetails.username}
          metaLabel="Trade"
          metaLabelClassName="font-medium text-amber-400/90"
          postedAt={modalPostDetails.postedAt}
        />
      }
      compactHeader={
        <CommentFocusCompactStrip
          userId={String(post.user_id ?? "")}
          username={modalPostDetails.username}
          avatarUrl={modalPostDetails.avatarUrl}
          meta={
            <>
              <FeedPostMetaRow
                label="Trade"
                labelClassName="font-medium text-amber-400/90"
                createdAt={modalPostDetails.postedAt}
              />
              <div className="mt-0.5 truncate text-xs font-medium text-gray-300">
                {pnlMeta}
              </div>
            </>
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
      collapsibleContent={
        <div className="min-w-0 space-y-3 overflow-hidden border-b border-white/10 px-4 py-4 text-xs md:text-sm">
          <div className="flex min-w-0 flex-wrap items-center justify-between gap-x-3 gap-y-1 md:flex-nowrap">
            <div className="flex min-w-0 items-center gap-3">
              <div
                className={`shrink-0 text-base font-semibold tabular-nums md:text-lg ${
                  modalPostDetails.pnlPositive
                    ? "text-emerald-400"
                    : "text-red-400"
                }`}
              >
                {formatSignedPnlDisplay(modalPostDetails.pnl)}
              </div>
              <div className="flex min-w-0 items-center gap-2 text-xs font-medium text-white md:text-sm">
                <span className="min-w-0 truncate">
                  {modalPostDetails.ticker} • {modalPostDetails.dir}
                </span>
                {modalPostDetails.acctNorm ? (
                  <span
                    className={`shrink-0 rounded-full px-2 py-0.5 text-[10px] md:text-xs ${getModeStyles(modalPostDetails.acctStyleKey)}`}
                  >
                    {modalPostDetails.acctNorm}
                  </span>
                ) : null}
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-2 text-xs text-gray-300 md:text-sm">
              {post.rr != null && post.rr !== "" ? (
                <span className="tabular-nums">RR {formatRR(post.rr)}</span>
              ) : null}
              {modalPostDetails.points !== null ? (
                <span className="rounded-md bg-white/10 px-2 py-0.5 text-[10px] text-gray-200 md:text-sm">
                  {formatPoints(modalPostDetails.points)} pts
                </span>
              ) : null}
            </div>
          </div>

          {modalPostDetails.publicDesc ? (
            <ExpandableText
              className="min-w-0 text-xs leading-relaxed text-white md:text-sm"
              textClassName="break-words text-white"
            >
              {modalPostDetails.publicDesc}
            </ExpandableText>
          ) : null}

          {modalPostDetails.timingTrade || attachedReel ? (
            <TradeCardTimingBlock
              trade={modalPostDetails.timingTrade ?? {}}
              onViewReel={
                attachedReel && onOpenAttachedReel
                  ? () => onOpenAttachedReel(post, attachedReel)
                  : undefined
              }
            />
          ) : null}
        </div>
      }
      comments={
        <FeedCommentsSection
          target={feedCommentTarget(pid, post)}
          user={user}
          comments={comments}
          commentSubmitting={commentSubmitting}
          draftSyncRef={draftSyncRef}
          listScrollRef={commentsScrollRef}
          onSubmitComment={(context, text, parentCommentId) =>
            onSubmitComment(context, text, parentCommentId)
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
        ariaLabel="Post details"
        title="Post"
        layout="split"
        onClose={onClose}
        splitMedia={splitMedia}
        splitPanel={splitPanel}
        suppressMobileSplitMedia={commentsFocused}
      />
      <ImageLightbox imageUrl={lightboxUrl} onClose={() => setLightboxUrl(null)} />
    </>
  )
}
