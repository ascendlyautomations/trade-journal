"use client"

import { commentLikeLabel, type CommentLikeMeta } from "@/lib/commentLikes"

type CommentLikeActionButtonProps = {
  meta: CommentLikeMeta
  onToggle: () => void
  disabled?: boolean
  className?: string
}

export default function CommentLikeActionButton({
  meta,
  onToggle,
  disabled = false,
  className = "",
}: CommentLikeActionButtonProps) {
  const label = commentLikeLabel(meta)

  return (
    <button
      type="button"
      disabled={disabled}
      onClick={(e) => {
        e.stopPropagation()
        onToggle()
      }}
      aria-label={meta.liked ? "Unlike comment" : "Like comment"}
      className={`inline-flex items-center gap-1 text-xs font-medium transition-colors disabled:pointer-events-none disabled:opacity-40 ${
        meta.liked
          ? "text-red-400 hover:text-red-300"
          : "text-gray-500 hover:text-gray-300"
      } ${className}`}
    >
      {label}
    </button>
  )
}
