"use client"

import { useCallback } from "react"
import ReplyComposerStrip from "@/app/components/replies/ReplyComposerStrip"
import type { ReplyTarget } from "@/lib/replyReference"

type FeedCommentComposerProps = {
  post: any
  user: any
  commentValue: string
  commentSubmitting: boolean
  replyTarget?: ReplyTarget | null
  onCancelReply?: () => void
  onCommentChange: (postId: string, value: string) => void
  onSubmitComment: (post: any) => void
}

function FeedCommentComposer({
  post,
  user,
  commentValue,
  commentSubmitting,
  replyTarget,
  onCancelReply,
  onCommentChange,
  onSubmitComment,
}: FeedCommentComposerProps) {
  const pid = String(post.id)

  const stopPropagation = useCallback((e: React.SyntheticEvent) => {
    e.stopPropagation()
  }, [])

  const handleChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      onCommentChange(pid, e.target.value)
    },
    [onCommentChange, pid]
  )

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      e.stopPropagation()
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault()
        if (!commentSubmitting) onSubmitComment(post)
      }
    },
    [commentSubmitting, onSubmitComment, post]
  )

  const handleSubmitClick = useCallback(
    (e: React.MouseEvent<HTMLButtonElement>) => {
      e.stopPropagation()
      onSubmitComment(post)
    },
    [onSubmitComment, post]
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
          id={`comment-input-${pid}`}
          type="text"
          placeholder={replyTarget ? "Write a reply…" : "Add a comment…"}
          value={commentValue}
          onChange={handleChange}
          onClick={stopPropagation}
          onFocus={stopPropagation}
          onKeyDown={handleKeyDown}
          className="flex-1 min-w-0 p-2 bg-[#1e293b] text-white rounded-lg border border-gray-600 text-sm placeholder:text-gray-500"
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
