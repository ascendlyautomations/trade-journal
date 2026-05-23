"use client"

import { memo, useCallback, useEffect, useMemo, useState, type MutableRefObject } from "react"
import { formatEST } from "@/lib/formatEST"
import {
  getModeStyles,
  postImageSrc,
  postPublicDescription,
  postTradeJoin,
} from "./feedPostHelpers"
import FeedPostActions from "./FeedPostActions"
import FeedPostBody from "./FeedPostBody"
import FeedCommentsSection from "./FeedCommentsSection"
import FeedPostHeader from "./FeedPostHeader"
import FeedPostScreenshot from "./FeedPostScreenshot"

export type FeedLikeMeta = { count: number; liked: boolean }

const EMPTY_LIKE_META: FeedLikeMeta = { count: 0, liked: false }
const EMPTY_COMMENTS: any[] = []

export type FeedPostCardProps = {
  post: any
  user: any
  likeMeta?: FeedLikeMeta
  comments?: any[]
  commentSubmitting: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  openCommentsRef?: MutableRefObject<Record<string, boolean>>
  detailOpen?: boolean
  onSelectPost: (post: any) => void
  onToggleLike: (post: any) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
}

function FeedPostCard({
  post,
  user,
  likeMeta = EMPTY_LIKE_META,
  comments = EMPTY_COMMENTS,
  commentSubmitting,
  draftSyncRef,
  openCommentsRef,
  detailOpen = false,
  onSelectPost,
  onToggleLike,
  onSubmitComment,
  onSharePost,
}: FeedPostCardProps) {
  const pid = String(post.id)
  const [commentsOpen, setCommentsOpen] = useState(
    () => !!openCommentsRef?.current[pid]
  )

  const handleToggleComments = useCallback(() => {
    setCommentsOpen((prev) => {
      const next = !prev
      if (openCommentsRef) {
        openCommentsRef.current[pid] = next
      }
      return next
    })
  }, [openCommentsRef, pid])

  useEffect(() => {
    if (!detailOpen && openCommentsRef) {
      setCommentsOpen(!!openCommentsRef.current[pid])
    }
  }, [detailOpen, openCommentsRef, pid])

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
    const accountTypeNorm = String(tradeRow?.account_type ?? "").trim().toLowerCase()
    return {
      tickerLabel: tradeRow?.ticker != null ? String(tradeRow.ticker) : "—",
      dirLabel: tradeRow?.direction != null ? String(tradeRow.direction) : "—",
      accountTypeNorm,
      accountTypeStyles: accountTypeNorm ? getModeStyles(accountTypeNorm) : "",
    }
  }, [tradeRow])
  const createdAtLabel = useMemo(
    () => formatEST(post.created_at),
    [post.created_at]
  )

  return (
    <article
      role="button"
      tabIndex={0}
      onClick={handleArticleClick}
      onKeyDown={handleArticleKeyDown}
      className="bg-white/5 border border-white/10 rounded-xl overflow-hidden shadow-lg shadow-black/20 cursor-pointer transition-all duration-200 hover:border-white/20 hover:shadow-xl hover:bg-white/[0.07]"
    >
      <FeedPostHeader
        userId={post.user_id}
        avatarUrl={avatarUrl}
        username={profileUsername}
      />

      <FeedPostScreenshot imageSrc={imageSrc} />

      <FeedPostActions
        post={post}
        user={user}
        comments={comments}
        likeMeta={likeMeta}
        commentsOpen={commentsOpen}
        onToggleLike={onToggleLike}
        onToggleComments={handleToggleComments}
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
        points={tradeRow?.points}
        publicDesc={publicDesc}
        createdAtLabel={createdAtLabel}
      />

      {commentsOpen && !detailOpen ? (
        <FeedCommentsSection
          post={post}
          user={user}
          comments={comments}
          commentSubmitting={commentSubmitting}
          draftSyncRef={draftSyncRef}
          onSubmitComment={onSubmitComment}
        />
      ) : null}
    </article>
  )
}

export default memo(FeedPostCard)

export { EMPTY_COMMENTS, EMPTY_LIKE_META }
