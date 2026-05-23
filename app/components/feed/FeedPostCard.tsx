"use client"

import { memo, useCallback, useMemo, type MutableRefObject } from "react"
import Link from "next/link"
import { formatEST } from "@/lib/formatEST"
import {
  getModeStyles,
  postImageSrc,
  postPublicDescription,
  postTradeJoin,
} from "./feedPostHelpers"
import FeedPostActions from "./FeedPostActions"
import FeedCommentsSection from "./FeedCommentsSection"

export type FeedLikeMeta = { count: number; liked: boolean }

const EMPTY_LIKE_META: FeedLikeMeta = { count: 0, liked: false }
const EMPTY_COMMENTS: any[] = []

export type FeedPostCardProps = {
  post: any
  user: any
  likeMeta?: FeedLikeMeta
  comments?: any[]
  commentsOpen: boolean
  commentSubmitting: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  onSelectPost: (post: any) => void
  onToggleLike: (post: any) => void
  onToggleComments: (postId: string) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
}

function FeedPostCard({
  post,
  user,
  likeMeta = EMPTY_LIKE_META,
  comments = EMPTY_COMMENTS,
  commentsOpen,
  commentSubmitting,
  draftSyncRef,
  onSelectPost,
  onToggleLike,
  onToggleComments,
  onSubmitComment,
  onSharePost,
}: FeedPostCardProps) {
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
  const tradeRow = useMemo(() => postTradeJoin(post), [post.trades])
  const publicDesc = useMemo(() => postPublicDescription(post), [post.trades])
  const pnl = useMemo(() => Number(post.pnl), [post.pnl])
  const pnlPositive = !Number.isNaN(pnl) && pnl >= 0
  const tickerLabel = tradeRow?.ticker != null ? String(tradeRow.ticker) : "—"
  const dirLabel = tradeRow?.direction != null ? String(tradeRow.direction) : "—"
  const accountTypeNorm = String(tradeRow?.account_type ?? "").trim().toLowerCase()

  return (
    <article
      role="button"
      tabIndex={0}
      onClick={handleArticleClick}
      onKeyDown={handleArticleKeyDown}
      className="bg-white/5 border border-white/10 rounded-xl overflow-hidden shadow-lg shadow-black/20 cursor-pointer transition-all duration-200 hover:border-white/20 hover:shadow-xl hover:bg-white/[0.07]"
    >
      <Link
        href={`/profile/${post.user_id}`}
        onClick={(e) => e.stopPropagation()}
        className="flex items-center gap-3 p-4 border-b border-white/5 hover:bg-white/5 transition-colors"
      >
        {post.profiles?.avatar_url ? (
          <img
            src={post.profiles.avatar_url}
            alt=""
            loading="lazy"
            decoding="async"
            className="w-10 h-10 rounded-full object-cover ring-2 ring-white/10 shrink-0"
          />
        ) : (
          <div
            className="w-10 h-10 rounded-full bg-gradient-to-br from-blue-500/40 to-emerald-500/40 ring-2 ring-white/10 shrink-0"
            aria-hidden
          />
        )}
        <span className="font-semibold text-sm sm:text-base truncate text-white">
          {post.profiles?.username || "User"}
        </span>
      </Link>

      {imageSrc ? (
        <div className="w-full bg-black/30">
          <img
            src={imageSrc}
            alt=""
            loading="lazy"
            decoding="async"
            className="w-full max-h-[400px] object-cover block"
          />
        </div>
      ) : null}

      <FeedPostActions
        post={post}
        user={user}
        comments={comments}
        likeMeta={likeMeta}
        commentsOpen={commentsOpen}
        onToggleLike={onToggleLike}
        onToggleComments={onToggleComments}
        onSharePost={onSharePost}
      />

      <div className="space-y-3 px-4 pb-3">
        <div className="mt-2 flex items-center justify-between gap-3">
          <div className="flex min-w-0 items-center gap-3">
            <div
              className={`shrink-0 text-lg font-semibold tabular-nums ${
                pnlPositive ? "text-emerald-400" : "text-red-400"
              }`}
            >
              {Number.isNaN(pnl) ? "—" : `${pnlPositive ? "+" : ""}$${pnl}`}
            </div>

            <div className="flex min-w-0 items-center gap-2 text-sm font-medium text-white">
              <span className="truncate">
                {tickerLabel} • {dirLabel}
              </span>
              {accountTypeNorm ? (
                <span
                  className={`px-2 py-0.5 text-xs rounded-full ${getModeStyles(accountTypeNorm)}`}
                >
                  {accountTypeNorm}
                </span>
              ) : null}
            </div>
          </div>

          <div className="flex shrink-0 items-center gap-2 text-sm text-gray-300">
            {post.rr != null && post.rr !== "" ? (
              <span className="tabular-nums">RR {post.rr}</span>
            ) : null}
            {post.points !== null && post.points !== undefined ? (
              <span className="rounded-md bg-white/10 px-2 py-0.5 text-gray-200">
                {post.points} pts
              </span>
            ) : null}
          </div>
        </div>

        {publicDesc ? (
          <p className="px-1 text-sm leading-relaxed text-white">{publicDesc}</p>
        ) : null}

        <p className="text-xs text-white/40">{formatEST(post.created_at)}</p>
      </div>

      <FeedCommentsSection
        post={post}
        user={user}
        comments={comments}
        likeMeta={likeMeta}
        commentsOpen={commentsOpen}
        commentSubmitting={commentSubmitting}
        draftSyncRef={draftSyncRef}
        onToggleLike={onToggleLike}
        onToggleComments={onToggleComments}
        onSubmitComment={onSubmitComment}
        onSharePost={onSharePost}
      />
    </article>
  )
}

export default memo(FeedPostCard)

export { EMPTY_COMMENTS, EMPTY_LIKE_META }
