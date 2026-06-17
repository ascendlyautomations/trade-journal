"use client"

import { useCallback } from "react"

type FeedCommentComposerProps = {
  post: any
  user: any
  commentValue: string
  commentSubmitting: boolean
  onCommentChange: (postId: string, value: string) => void
  onSubmitComment: (post: any) => void
}

function FeedCommentComposer({
  post,
  user,
  commentValue,
  commentSubmitting,
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
      className="flex gap-2 mt-2"
      onClick={stopPropagation}
      onKeyDown={stopPropagation}
    >
      <input
        id={`comment-input-${pid}`}
        type="text"
        placeholder="Add a comment…"
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
  )
}

export default FeedCommentComposer
