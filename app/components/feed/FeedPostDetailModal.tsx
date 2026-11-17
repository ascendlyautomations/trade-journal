"use client"

import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react"
import MobileWebOpenInAppLink from "@/app/components/mobile/MobileWebOpenInAppLink"
import DetailModalShell, {
  scrollModalCommentsPane,
} from "@/app/components/ui/DetailModalShell"
import { mobileWebOpenInAppContentLink } from "@/lib/mobileWebOpenInApp"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import TradeDetailMediaWithClipOverlay from "@/app/components/trade/TradeDetailMediaWithClipOverlay"
import PublicSocialTradeStatsPanel from "@/app/components/trade/PublicSocialTradeStatsPanel"
import { PostInteractionsEngagement } from "@/app/components/PostInteractions"
import { vaultRefFromFeedItem } from "@/lib/vault/refs"
import CopyTradedBadge from "@/app/components/trade/CopyTradedBadge"
import { publicSocialHeaderAccountBadge } from "@/lib/tradeSocialDetailDisplay"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import { formatRR, formatSignedPnlDisplay } from "@/lib/formatDisplay"
import { isCopyTradedMode } from "@/lib/tradeMode"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostHeader from "./FeedPostHeader"
import FeedPostMetaRow from "./FeedPostMetaRow"
import {
  feedCommentTarget,
  postAttachedReel,
  postImageSrc,
  postPublicDescription,
  postTradeJoin,
} from "./feedPostHelpers"
import type { ReelRow } from "@/lib/reels"
import {
  detailModalEngagementInPanel,
  DETAIL_MODAL_MEDIA_ACTIONS_WRAP_CLASS,
} from "@/app/components/ui/detailModalEngagement"
import { useMaxMdViewport } from "@/lib/useMaxMdViewport"
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
  onSubmitComment: (
    post: any,
    text: string,
    parentCommentId?: string | null,
    retryTempId?: string | null
  ) => Promise<boolean>
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
  const isMobile = useMaxMdViewport()

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
      pnl,
      pnlPositive: !Number.isNaN(pnl) && pnl >= 0,
      timingTrade: tradeJoin,
      showCopyBadge: isCopyTradedMode(tradeJoin),
      postedAt: post.created_at,
      avatarUrl,
      username: post.profiles?.username || "User",
    }
  }, [post])

  const attachedReel = useMemo(() => postAttachedReel(post), [post])

  const openAttachedReel = useCallback(() => {
    if (attachedReel && onOpenAttachedReel) {
      onOpenAttachedReel(post, attachedReel)
    }
  }, [attachedReel, onOpenAttachedReel, post])

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

  const splitMedia = (
    <TradeDetailMediaWithClipOverlay
      imageSrc={modalPostDetails.imageSrc}
      attachedReel={attachedReel}
      onOpenImage={setLightboxUrl}
      onOpenClip={
        attachedReel && onOpenAttachedReel ? openAttachedReel : undefined
      }
    />
  )

  const hasMedia =
    modalPostDetails.imageSrc != null || (attachedReel != null && onOpenAttachedReel != null)
  const showEngagementInPanel = detailModalEngagementInPanel(
    hasMedia,
    commentsFocused,
    isMobile
  )

  const engagementRow = (
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
      vaultContentRef={vaultRefFromFeedItem(post)}
    />
  )

  const engagementUnderMedia = !showEngagementInPanel ? (
    <div className={DETAIL_MODAL_MEDIA_ACTIONS_WRAP_CLASS}>{engagementRow}</div>
  ) : null

  const splitPanel = (
    <MobileCommentFocusLayout
      commentsFocused={commentsFocused}
      mobileMedia={
        hasMedia && !commentsFocused ? (
          <div className="flex flex-col">
            {splitMedia}
            {engagementUnderMedia}
          </div>
        ) : undefined
      }
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
      engagement={showEngagementInPanel ? engagementRow : undefined}
      collapsibleContent={
        <div className="min-w-0 space-y-2 overflow-hidden border-b border-white/10 px-3 py-2 text-xs md:px-4 md:text-sm">
          <div className="flex min-w-0 items-start justify-between gap-3">
            <div className="min-w-0 space-y-0.5">
              <div className="flex min-w-0 flex-wrap items-baseline gap-x-1.5">
                <span className="text-base font-semibold text-white md:text-lg">
                  {modalPostDetails.ticker}
                </span>
                {!modalPostDetails.showCopyBadge &&
                modalPostDetails.timingTrade &&
                publicSocialHeaderAccountBadge(modalPostDetails.timingTrade) ? (
                  <>
                    <span className="text-sm font-medium text-gray-500">|</span>
                    <span className="text-sm font-medium text-gray-400">
                      {publicSocialHeaderAccountBadge(modalPostDetails.timingTrade)}
                    </span>
                  </>
                ) : null}
              </div>
              <span className="text-[11px] font-semibold uppercase tracking-wide text-gray-300">
                {modalPostDetails.dir}
              </span>
              {modalPostDetails.showCopyBadge ? (
                <CopyTradedBadge
                  trade={modalPostDetails.timingTrade}
                  className="mt-1"
                />
              ) : null}
            </div>
            <div className="shrink-0 text-right">
              <p
                className={`text-base font-semibold tabular-nums md:text-lg ${
                  modalPostDetails.pnlPositive
                    ? "text-emerald-400"
                    : "text-red-400"
                }`}
              >
                {formatSignedPnlDisplay(modalPostDetails.pnl)}
              </p>
              {post.rr != null && post.rr !== "" ? (
                <p className="text-xs font-semibold tabular-nums text-gray-400 md:text-sm">
                  {formatRR(post.rr)} R:R
                </p>
              ) : null}
            </div>
          </div>

          {modalPostDetails.publicDesc ? (
            <p className="whitespace-pre-wrap text-sm leading-relaxed text-white">
              {modalPostDetails.publicDesc}
            </p>
          ) : null}

          {modalPostDetails.timingTrade ? (
            <PublicSocialTradeStatsPanel trade={modalPostDetails.timingTrade} />
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
        ariaLabel="Post details"
        title="Post"
        headerAccessory={
          <MobileWebOpenInAppLink
            link={mobileWebOpenInAppContentLink("post", pid)}
            variant="inline"
          />
        }
        layout="split"
        onClose={onClose}
        splitMedia={splitMedia}
        splitMediaActions={
          hasMedia && !showEngagementInPanel ? engagementRow : undefined
        }
        splitPanel={splitPanel}
        suppressMobileSplitMedia
      />
      <ImageLightbox imageUrl={lightboxUrl} onClose={() => setLightboxUrl(null)} />
    </>
  )
}
