"use client"

import { memo, useCallback, useMemo, type MutableRefObject } from "react"
import {
  getModeStyles,
  normalizeFeedAccountType,
  postImageSrc,
  postPublicDescription,
  postTradeJoin,
} from "./feedPostHelpers"
import { formatPublicAccountTypeLabel } from "@/lib/publicAccountPrivacy"
import FeedPostActions from "./FeedPostActions"
import FeedPostBody from "./FeedPostBody"
import FeedPostHeader from "./FeedPostHeader"
import FeedPostScreenshot from "./FeedPostScreenshot"
import { postAttachedReel } from "./feedPostHelpers"
import type { ReelRow } from "@/lib/reels"

export type FeedLikeMeta = { count: number; liked: boolean }

const EMPTY_LIKE_META: FeedLikeMeta = { count: 0, liked: false }
const EMPTY_COMMENTS: any[] = []

export type FeedPostCardProps = {
  post: any
  user: any
  likeMeta?: FeedLikeMeta
  likeBusy?: boolean
  commentCount?: number
  comments?: any[]
  mediaPriority?: boolean
  commentSubmitting?: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  /** Read-only preview: no post detail navigation. */
  preview?: boolean
  onSelectPost: (post: any) => void
  onOpenComments: (post: any) => void
  onToggleLike: (post: any) => void
  onSubmitComment?: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
  onOpenAttachedReel?: (post: any, reel: ReelRow) => void
  /** Shared aspect-ratio media frame for homepage featured trade cards (contain, no re-crop). */
  screenshotFixedFrameClassName?: string
}

function FeedPostCard({
  post,
  user,
  likeMeta = EMPTY_LIKE_META,
  likeBusy = false,
  commentCount,
  comments = EMPTY_COMMENTS,
  mediaPriority = false,
  preview = false,
  onSelectPost,
  onOpenComments,
  onToggleLike,
  onSharePost,
  onOpenAttachedReel,
  screenshotFixedFrameClassName,
}: FeedPostCardProps) {
  const handleOpenComments = useCallback(() => {
    onOpenComments(post)
  }, [onOpenComments, post])

  const handleArticleClick = useCallback(() => {
    onSelectPost(post)
  }, [onSelectPost, post])

  const handleArticleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault()
        onSelectPost(post)
      }
    },
    [onSelectPost, post]
  )

  const imageSrc = useMemo(() => postImageSrc(post.image_url), [post.image_url])
  const avatarUrl = useMemo(() => {
    const raw = post.profiles?.avatar_url
    if (raw == null) return null
    const trimmed = String(raw).trim()
    return trimmed !== "" ? trimmed : null
  }, [post.profiles?.avatar_url])
  const profileUsername = post.profiles?.username || "User"
  const tradeRow = useMemo(() => postTradeJoin(post), [post])
  const attachedReel = useMemo(() => postAttachedReel(post), [post])
  const publicDesc = useMemo(() => postPublicDescription(post), [post])
  const pnl = useMemo(() => Number(post.pnl), [post.pnl])
  const pnlPositive = !Number.isNaN(pnl) && pnl >= 0
  const tradeDisplay = useMemo(() => {
    const accountTypeNorm = normalizeFeedAccountType(tradeRow?.account_type)
    const accountTypeLabel =
      formatPublicAccountTypeLabel(accountTypeNorm) ?? accountTypeNorm
    return {
      tickerLabel: tradeRow?.ticker != null ? String(tradeRow.ticker) : "—",
      dirLabel: tradeRow?.direction != null ? String(tradeRow.direction) : "—",
      accountTypeNorm: accountTypeLabel,
      accountTypeStyles: accountTypeNorm ? getModeStyles(accountTypeNorm) : "",
    }
  }, [tradeRow])
  return (
    <article
      role={preview ? "article" : "button"}
      tabIndex={preview ? undefined : 0}
      onClick={preview ? undefined : handleArticleClick}
      onKeyDown={preview ? undefined : handleArticleKeyDown}
      className={
        preview
          ? "bg-white/5 border border-white/10 rounded-xl overflow-hidden shadow-lg shadow-black/20"
          : "bg-white/5 border border-white/10 rounded-xl overflow-hidden shadow-lg shadow-black/20 cursor-pointer transition-all duration-200 hover:border-white/20 hover:shadow-xl hover:bg-white/[0.07]"
      }
    >
      <FeedPostHeader
        userId={post.user_id}
        avatarUrl={avatarUrl}
        username={profileUsername}
        metaLabel="Trade"
        metaLabelClassName="font-medium text-amber-400/90"
        postedAt={post.created_at}
        preview={preview}
      />

      <FeedPostScreenshot
        imageSrc={imageSrc}
        priority={mediaPriority}
        fixedFrameClassName={screenshotFixedFrameClassName}
      />

      <FeedPostActions
        post={post}
        user={user}
        commentCount={commentCount ?? comments.length}
        likeMeta={likeMeta}
        likeBusy={likeBusy}
        onToggleLike={onToggleLike}
        onOpenComments={handleOpenComments}
        onSharePost={onSharePost}
      />

      <FeedPostBody
        pnl={pnl}
        pnlPositive={pnlPositive}
        tickerLabel={tradeDisplay.tickerLabel}
        dirLabel={tradeDisplay.dirLabel}
        accountTypeNorm={tradeDisplay.accountTypeNorm}
        accountTypeStyles={tradeDisplay.accountTypeStyles}
        rr={post.rr}
        publicDesc={publicDesc}
        timingTrade={tradeRow}
        onViewReel={
          attachedReel
            ? () => {
                // Preview: show Feed-identical View Clip badge; open only when wired.
                onOpenAttachedReel?.(post, attachedReel)
              }
            : undefined
        }
      />
    </article>
  )
}

export default memo(FeedPostCard)

export { EMPTY_COMMENTS, EMPTY_LIKE_META }
