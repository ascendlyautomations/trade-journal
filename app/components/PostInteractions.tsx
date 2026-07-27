"use client"

import FeedCommentItem from "@/app/components/feed/FeedCommentItem"
import EngagementCountButton from "@/app/components/EngagementCountButton"
import ActionButton from "@/app/components/ui/ActionButton"
import { useHydrationReady } from "@/lib/useHydrationReady"

type LikeMeta = {
  count: number
  liked: boolean
}

type PostInteractionsBaseProps = {
  post: any
  user: any
  comments: any[]
  commentCount?: number
  likeMeta: LikeMeta
  likeBusy?: boolean
  commentsOpen?: boolean
  commentValue?: string
  commentSubmitting?: boolean
  onToggleLike: (post: any) => void
  onOpenComments: (postId: string) => void
  onCommentChange: (postId: string, value: string) => void
  onSubmitComment: (post: any) => void
  onSharePost?: (post: any) => void
  stopPropagation?: boolean
}

const guard = (stop: boolean) =>
  stop
    ? {
        onClick: (e: React.MouseEvent) => e.stopPropagation(),
        onKeyDown: (e: React.KeyboardEvent) => e.stopPropagation(),
      }
    : {}

/** Likes, comments, and share controls in a single row. */
export function PostInteractionsEngagement({
  post,
  user,
  comments,
  commentCount,
  likeMeta,
  likeBusy = false,
  onToggleLike,
  onOpenComments,
  onSharePost,
  stopPropagation = false,
  className = "",
}: Omit<
  PostInteractionsBaseProps,
  | "commentsOpen"
  | "commentValue"
  | "commentSubmitting"
  | "onCommentChange"
  | "onSubmitComment"
> & { className?: string }) {
  const pid = String(post.id)
  const hydrationReady = useHydrationReady()
  // Prevent double-taps while syncing, but keep full opacity (pulse instead of gray-out).
  const likeDisabled = !hydrationReady || !user

  return (
    <div className={`text-sm ${className}`.trim()} {...guard(stopPropagation)}>
      <div className="flex items-center gap-3">
        <EngagementCountButton
          variant="boxed"
          icon={<span>{likeMeta.liked ? "❤️" : "🤍"}</span>}
          count={likeMeta.count}
          ariaLabel={likeMeta.liked ? "Unlike" : "Like"}
          disabled={likeDisabled || likeBusy}
          syncing={likeBusy}
          likedPop={likeMeta.liked}
          onClick={(e) => {
            if (stopPropagation) e.stopPropagation()
            if (likeBusy) return
            onToggleLike(post)
          }}
          className={
            likeMeta.liked ? "text-red-400 hover:text-red-300" : undefined
          }
        />
        <EngagementCountButton
          variant="boxed"
          icon={<span>💬</span>}
          count={commentCount ?? comments.length}
          ariaLabel="View comments"
          onClick={(e) => {
            if (stopPropagation) e.stopPropagation()
            onOpenComments(pid)
          }}
        />
        {onSharePost ? (
          <button
            type="button"
            onClick={(e) => {
              if (stopPropagation) e.stopPropagation()
              onSharePost(post)
            }}
            className="flex items-center justify-center w-9 h-9 rounded-lg bg-white/5 hover:bg-white/10 transition text-gray-300 hover:text-white"
            aria-label="Share post"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-4 w-4"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              aria-hidden
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M12 16V4m0 0l-4 4m4-4l4 4M4 20h16"
              />
            </svg>
          </button>
        ) : null}
      </div>
    </div>
  )
}

/** Comment thread + composer (only when `commentsOpen`). */
export function PostInteractionsComments({
  post,
  user,
  comments,
  commentsOpen = false,
  commentValue = "",
  commentSubmitting = false,
  onCommentChange,
  onSubmitComment,
  stopPropagation = false,
  className = "",
}: PostInteractionsBaseProps & { className?: string }) {
  const pid = String(post.id)
  if (!commentsOpen) return null

  return (
    <div
      className={`space-y-3 border-t border-white/10 pt-3 ${className}`.trim()}
      {...guard(stopPropagation)}
    >
      <div className="space-y-2">
        {comments.map((c: any) => (
          <FeedCommentItem
            key={c.id}
            comment={c}
            stopPropagation={stopPropagation}
          />
        ))}
      </div>

      {user ? (
        <div
          className="flex gap-2 mt-2"
          onClick={(e) => {
            if (stopPropagation) e.stopPropagation()
          }}
          onKeyDown={(e) => {
            if (stopPropagation) e.stopPropagation()
          }}
        >
          <input
            id={`comment-input-${pid}`}
            type="text"
            placeholder="Add a comment…"
            value={commentValue}
            onChange={(e) => onCommentChange(pid, e.target.value)}
            onClick={(e) => {
              if (stopPropagation) e.stopPropagation()
            }}
            onFocus={(e) => {
              if (stopPropagation) e.stopPropagation()
            }}
            onKeyDown={(e) => {
              if (stopPropagation) e.stopPropagation()
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault()
                if (!commentSubmitting) onSubmitComment(post)
              }
            }}
            className="flex-1 min-w-0 p-2 bg-[#1e293b] text-white rounded-lg border border-gray-600 text-sm placeholder:text-gray-400"
          />
          <ActionButton
            type="button"
            disabled={!commentValue.trim()}
            syncing={commentSubmitting}
            syncingLabel="Posting…"
            onClick={(e) => {
              if (stopPropagation) e.stopPropagation()
              onSubmitComment(post)
            }}
            className="bg-blue-500 px-3 rounded-lg text-white text-sm font-medium disabled:opacity-40 shrink-0"
          >
            Post
          </ActionButton>
        </div>
      ) : null}
    </div>
  )
}

type PostInteractionsProps = PostInteractionsBaseProps & {
  className?: string
  commentsOpen?: boolean
}

export default function PostInteractions({
  className = "",
  commentsOpen = true,
  ...rest
}: PostInteractionsProps) {
  const outerClass =
    `flex flex-col gap-2 pt-1 border-t border-white/5 ${className}`.trim()

  return (
    <div className={outerClass} {...guard(rest.stopPropagation ?? false)}>
      <PostInteractionsEngagement {...rest} />
      <PostInteractionsComments {...rest} commentsOpen={commentsOpen} />
    </div>
  )
}
