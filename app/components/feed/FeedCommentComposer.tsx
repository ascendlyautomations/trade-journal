"use client"

import { useCallback } from "react"
import ReplyComposerStrip from "@/app/components/replies/ReplyComposerStrip"
import ActionButton from "@/app/components/ui/ActionButton"
import type { CommentReplyTarget } from "@/lib/commentReplyUx"
import {
  COMMENT_PRIVATE_TRADE_DISCLAIMER,
  canPostCommentWithAttachment,
} from "@/lib/commentSharedTrade"

type PendingTrade = {
  id: string
  ticker?: string
  direction?: string
  is_public?: boolean | null
}

type FeedCommentComposerProps = {
  contentId: string
  submitContext: unknown
  user: any
  commentValue: string
  commentSubmitting: boolean
  replyTarget?: CommentReplyTarget | null
  onCancelReply?: () => void
  onCommentChange: (contentId: string, value: string) => void
  onSubmitComment: (submitContext: unknown) => void
  pendingSharedTrade?: PendingTrade | null
  onAttachTrade?: () => void
  onClearAttachedTrade?: () => void
}

function FeedCommentComposer({
  contentId,
  submitContext,
  user,
  commentValue,
  commentSubmitting,
  replyTarget,
  onCancelReply,
  onCommentChange,
  onSubmitComment,
  pendingSharedTrade,
  onAttachTrade,
  onClearAttachedTrade,
}: FeedCommentComposerProps) {
  const stopPropagation = useCallback((e: React.SyntheticEvent) => {
    e.stopPropagation()
  }, [])

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      onCommentChange(contentId, e.target.value)
    },
    [contentId, onCommentChange]
  )

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      e.stopPropagation()
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        if (
          !commentSubmitting &&
          canPostCommentWithAttachment(commentValue, pendingSharedTrade?.id)
        ) {
          onSubmitComment(submitContext)
        }
      }
    },
    [
      commentSubmitting,
      commentValue,
      onSubmitComment,
      pendingSharedTrade?.id,
      submitContext,
    ]
  )

  const handleSubmitClick = useCallback(
    (e: React.MouseEvent<HTMLButtonElement>) => {
      e.stopPropagation()
      onSubmitComment(submitContext)
    },
    [onSubmitComment, submitContext]
  )

  const canPost = canPostCommentWithAttachment(commentValue, pendingSharedTrade?.id)

  if (!user) return null

  return (
    <div
      className="mt-2 flex flex-col gap-2"
      onClick={stopPropagation}
      onKeyDown={stopPropagation}
    >
      {replyTarget ? (
        <ReplyComposerStrip
          authorName={replyTarget.authorName}
          preview={replyTarget.preview}
          onCancel={() => onCancelReply?.()}
        />
      ) : null}
      {pendingSharedTrade ? (
        <div className="flex items-start justify-between gap-2 rounded-lg border border-white/10 bg-white/5 px-2 py-1.5 text-xs">
          <div className="min-w-0">
            <p className="font-medium text-white">
              {pendingSharedTrade.ticker ?? "Trade"} • {pendingSharedTrade.direction ?? ""}
            </p>
            {pendingSharedTrade.is_public === false ? (
              <p className="mt-0.5 text-gray-400">{COMMENT_PRIVATE_TRADE_DISCLAIMER}</p>
            ) : null}
          </div>
          <button
            type="button"
            className="shrink-0 text-gray-400 hover:text-white"
            onClick={(e) => {
              e.stopPropagation()
              onClearAttachedTrade?.()
            }}
            aria-label="Remove attached trade"
          >
            ✕
          </button>
        </div>
      ) : null}
      <div className="flex gap-2">
        {onAttachTrade ? (
          <button
            type="button"
            aria-label="Attach trade"
            onClick={(e) => {
              e.stopPropagation()
              onAttachTrade()
            }}
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-gray-600 bg-[#1e293b] text-lg text-blue-400"
          >
            +
          </button>
        ) : null}
        <input
          id={`comment-input-${contentId}`}
          type="text"
          placeholder={replyTarget ? "Add to reply…" : "Add a comment…"}
          value={commentValue}
          onChange={handleChange}
          onClick={stopPropagation}
          onFocus={stopPropagation}
          onKeyDown={handleKeyDown}
          className="flex-1 min-w-0 p-2 bg-[#1e293b] text-white rounded-lg border border-gray-600 text-sm placeholder:text-gray-400"
        />
        <ActionButton
          type="button"
          disabled={!canPost}
          syncing={commentSubmitting}
          syncingLabel="Posting…"
          onClick={handleSubmitClick}
          className="bg-blue-500 px-3 rounded-lg text-white text-sm font-medium disabled:opacity-40 shrink-0"
        >
          Post
        </ActionButton>
      </div>
    </div>
  )
}

export default FeedCommentComposer