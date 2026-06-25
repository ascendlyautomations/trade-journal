"use client"

import { memo, useCallback, useMemo, type MutableRefObject } from "react"
import { formatSocialTimestamp } from "@/lib/formatRelativeTime"
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

export type FeedLikeMeta = { count: number; liked: boolean }

const EMPTY_LIKE_META: FeedLikeMeta = { count: 0, liked: false }
const EMPTY_COMMENTS: any[] = []

export type FeedPostCardProps = {
  post: any
  user: any
  likeMeta?: FeedLikeMeta
  likeBusy?: boolean
  comments?: any[]
  commentSubmitting: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  /** Read-only preview: no post detail navigation. */
  preview?: boolean
  onSelectPost: (post: any) => void
  onOpenComments: (post: any) => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
}

function FeedPostCard({
  post,
  user,
  likeMeta = EMPTY_LIKE_META,
  likeBusy = false,
  comments = EMPTY_COMMENTS,
  commentSubmitting: _commentSubmitting,
  draftSyncRef: _draftSyncRef,
  preview = false,
  onSelectPost,
  onOpenComments,
  onToggleLike,
  onSubmitComment: _onSubmitComment,
  onSharePost,
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
  const tradeRow = useMemo(() => postTradeJoin(post), [post.trades])
  const publicDesc = useMemo(() => postPublicDescription(post), [post.trades])
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
  const createdAtLabel = useMemo(
    () => formatSocialTimestamp(post.created_at),
    [post.created_at]
  )

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
        preview={preview}
      />

      <FeedPostScreenshot imageSrc={imageSrc} />

      <FeedPostActions
        post={post}
        user={user}
        comments={comments}
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
        createdAtLabel={createdAtLabel}
      />
    </article>
  )
}

export default memo(FeedPostCard)

export { EMPTY_COMMENTS, EMPTY_LIKE_META }
