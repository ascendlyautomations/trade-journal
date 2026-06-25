"use client"

import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react"
import DetailModalShell, {
  scrollModalCommentsPane,
} from "@/app/components/ui/DetailModalShell"
import DetailModalImage from "@/app/components/ui/DetailModalImage"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import { formatEST } from "@/lib/formatEST"
import {
  formatPoints,
  formatRR,
  formatSignedPnlDisplay,
} from "@/lib/formatDisplay"
import { resolveTradePoints } from "@/lib/resolveTradePoints"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostHeader from "./FeedPostHeader"
import {
  getModeStyles,
  postImageSrc,
  postPublicDescription,
  postTradeJoin,
} from "./feedPostHelpers"
import { formatPublicAccountTypeLabel } from "@/lib/publicAccountPrivacy"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedPostDetailModalProps = {
  post: any
  user: any
  comments: any[]
  likeMeta: FeedLikeMeta
  likeBusy?: boolean
  commentSubmitting: boolean
  draftSyncRef: MutableRefObject<Record<string, string>>
  openCommentsRef: MutableRefObject<Record<string, boolean>>
  onClose: () => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onDeleteComment?: (comment: any) => Promise<boolean>
  onSharePost: (post: any) => void
}

export default function FeedPostDetailModal({
  post,
  user,
  comments,
  likeMeta,
  likeBusy = false,
  commentSubmitting,
  draftSyncRef,
  openCommentsRef,
  onClose,
  onToggleLike,
  onSubmitComment,
  onDeleteComment,
  onSharePost,
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
      createdAtLabel: formatEST(post.created_at),
      avatarUrl,
      username: post.profiles?.username || "User",
    }
  }, [post])

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
        />
      }
      compactHeader={
        <CommentFocusCompactStrip
          userId={String(post.user_id ?? "")}
          username={modalPostDetails.username}
          avatarUrl={modalPostDetails.avatarUrl}
          timestamp={post.created_at}
          meta={pnlMeta}
          onExpand={() => setCommentsFocused(false)}
        />
      }
      engagement={
        <PostInteractionsEngagement
          post={post}
          user={user}
          comments={comments}
          likeMeta={likeMeta}
          likeBusy={likeBusy}
          onToggleLike={onToggleLike}
          onOpenComments={() => focusComments()}
          onSharePost={onSharePost}
        />
      }
      collapsibleContent={
        <div className="space-y-3 border-b border-white/10 px-4 py-4 text-sm">
          <div className="flex items-center justify-between gap-3">
            <div className="flex min-w-0 items-center gap-3">
              <div
                className={`shrink-0 text-lg font-semibold tabular-nums ${
                  modalPostDetails.pnlPositive
                    ? "text-emerald-400"
                    : "text-red-400"
                }`}
              >
                {formatSignedPnlDisplay(modalPostDetails.pnl)}
              </div>
              <div className="flex min-w-0 items-center gap-2 text-sm font-medium text-white">
                <span className="truncate">
                  {modalPostDetails.ticker} • {modalPostDetails.dir}
                </span>
                {modalPostDetails.acctNorm ? (
                  <span
                    className={`rounded-full px-2 py-0.5 text-xs ${getModeStyles(modalPostDetails.acctStyleKey)}`}
                  >
                    {modalPostDetails.acctNorm}
                  </span>
                ) : null}
              </div>
            </div>
            <div className="flex shrink-0 items-center gap-2 text-sm text-gray-300">
              {post.rr != null && post.rr !== "" ? (
                <span className="tabular-nums">RR {formatRR(post.rr)}</span>
              ) : null}
              {modalPostDetails.points !== null ? (
                <span className="rounded-md bg-white/10 px-2 py-0.5 text-gray-200">
                  {formatPoints(modalPostDetails.points)} pts
                </span>
              ) : null}
            </div>
          </div>

          {modalPostDetails.publicDesc ? (
            <p className="text-sm leading-relaxed text-white">
              {modalPostDetails.publicDesc}
            </p>
          ) : null}

          {modalPostDetails.timingTrade ? (
            <TradeCardTimingBlock trade={modalPostDetails.timingTrade} />
          ) : null}

          <p className="text-xs text-white/40">
            {modalPostDetails.createdAtLabel}
          </p>
        </div>
      }
      comments={
        <FeedCommentsSection
          post={post}
          user={user}
          comments={comments}
          commentSubmitting={commentSubmitting}
          draftSyncRef={draftSyncRef}
          listScrollRef={commentsScrollRef}
          onSubmitComment={onSubmitComment}
          onDeleteComment={onDeleteComment}
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
