"use client"

import { useCallback, useEffect, useMemo, useState, type MutableRefObject } from "react"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"
import { formatEST } from "@/lib/formatEST"
import {
  formatPoints,
  formatRR,
  formatSignedPnlDisplay,
} from "@/lib/formatDisplay"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostScreenshot from "./FeedPostScreenshot"
import {
  getModeStyles,
  postImageSrc,
  postPublicDescription,
  postTradeJoin,
} from "./feedPostHelpers"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedPostDetailModalProps = {
  post: any
  user: any
  comments: any[]
  likeMeta: FeedLikeMeta
  commentSubmitting: boolean
  draftSyncRef: MutableRefObject<Record<string, string>>
  openCommentsRef: MutableRefObject<Record<string, boolean>>
  onClose: () => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
}

export default function FeedPostDetailModal({
  post,
  user,
  comments,
  likeMeta,
  commentSubmitting,
  draftSyncRef,
  openCommentsRef,
  onClose,
  onToggleLike,
  onSubmitComment,
  onSharePost,
}: FeedPostDetailModalProps) {
  const pid = String(post.id)
  const [commentsOpen, setCommentsOpen] = useState(
    () => !!openCommentsRef.current[pid]
  )

  useEffect(() => {
    setCommentsOpen(!!openCommentsRef.current[pid])
  }, [openCommentsRef, pid])

  const handleToggleComments = useCallback(() => {
    setCommentsOpen((prev) => {
      const next = !prev
      openCommentsRef.current[pid] = next
      return next
    })
  }, [openCommentsRef, pid])

  const modalPostDetails = useMemo(() => {
    const tradeJoin = postTradeJoin(post)
    const pnl = Number(post.pnl)
    return {
      imageSrc: postImageSrc(post.image_url),
      publicDesc: postPublicDescription(post),
      ticker: tradeJoin?.ticker != null ? String(tradeJoin.ticker) : "—",
      dir: tradeJoin?.direction != null ? String(tradeJoin.direction) : "—",
      acctNorm: String(tradeJoin?.account_type ?? "").trim().toLowerCase(),
      pnl,
      pnlPositive: !Number.isNaN(pnl) && pnl >= 0,
      points: tradeJoin?.points,
      timingTrade: tradeJoin,
      createdAtLabel: formatEST(post.created_at),
    }
  }, [post])

  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") onClose()
    }
    window.addEventListener("keydown", onKey)
    return () => window.removeEventListener("keydown", onKey)
  }, [onClose])

  const handleBackdropClick = useCallback(() => {
    onClose()
  }, [onClose])

  const stopPropagation = useCallback((e: React.MouseEvent) => {
    e.stopPropagation()
  }, [])

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4"
      onClick={handleBackdropClick}
    >
      <div
        className="relative w-full max-w-2xl rounded-xl bg-[#0f172a] p-4"
        onClick={stopPropagation}
      >
        <button
          type="button"
          onClick={onClose}
          className="absolute right-2 top-2 text-xl text-white"
          aria-label="Close"
        >
          ✕
        </button>

        <FeedPostScreenshot
          imageSrc={modalPostDetails.imageSrc}
          imgClassName="w-full max-h-[400px] rounded-lg object-cover"
          wrapperClassName=""
        />

        <div className="mt-3 border-t border-white/10 pt-3">
          <div className="min-w-0">
            <PostInteractionsEngagement
              post={post}
              user={user}
              comments={comments}
              likeMeta={likeMeta}
              commentsOpen={commentsOpen}
              onToggleLike={onToggleLike}
              onToggleComments={(_postId) => handleToggleComments()}
              onSharePost={onSharePost}
            />
          </div>
        </div>

        <div className="mt-3 space-y-3 text-sm">
          <div className="mt-2 flex items-center justify-between gap-3">
            <div className="flex min-w-0 items-center gap-3">
              <div
                className={`shrink-0 text-lg font-semibold tabular-nums ${
                  modalPostDetails.pnlPositive ? "text-emerald-400" : "text-red-400"
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
                    className={`px-2 py-0.5 text-xs rounded-full ${getModeStyles(modalPostDetails.acctNorm)}`}
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
              {modalPostDetails.points !== null &&
              modalPostDetails.points !== undefined ? (
                <span className="rounded-md bg-white/10 px-2 py-0.5 text-gray-200">
                  {formatPoints(modalPostDetails.points)} pts
                </span>
              ) : null}
            </div>
          </div>

          {modalPostDetails.publicDesc ? (
            <p className="text-white text-sm leading-relaxed">
              {modalPostDetails.publicDesc}
            </p>
          ) : null}

          {modalPostDetails.timingTrade ? (
            <TradeCardTimingBlock trade={modalPostDetails.timingTrade} />
          ) : null}

          <p className="text-xs text-white/40">{modalPostDetails.createdAtLabel}</p>
        </div>

        {commentsOpen ? (
          <FeedCommentsSection
            post={post}
            user={user}
            comments={comments}
            commentSubmitting={commentSubmitting}
            draftSyncRef={draftSyncRef}
            onSubmitComment={onSubmitComment}
          />
        ) : null}
      </div>
    </div>
  )
}
