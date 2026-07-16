"use client"

import { useCallback } from "react"
import ReplyComposerStrip from "@/app/components/replies/ReplyComposerStrip"
import type { CommentReplyTarget } from "@/lib/commentReplyUx"

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
        if (!commentSubmitting) onSubmitComment(submitContext)
      }
    },
    [commentSubmitting, onSubmitComment, submitContext]
  )

  const handleSubmitClick = useCallback(
    (e: React.MouseEvent<HTMLButtonElement>) => {
      e.stopPropagation()
      onSubmitComment(submitContext)
    },
    [onSubmitComment, submitContext]
  )

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
      <div className="flex gap-2">
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
        <button
          type="button"
          disabled={commentSubmitting || !commentValue.trim()}
          onClick={handleSubmitClick}
          className="bg-blue-500 px-3 rounded-lg text-white text-sm font-medium disabled:opacity-40 shrink-0"
        >
          {commentSubmitting ? "…" : "Post"}
        </button>
      </div>
    </div>
  )
}

export default FeedCommentComposer
