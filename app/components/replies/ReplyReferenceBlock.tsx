"use client"

import {
  previewTextFromComment,
  previewTextFromMessage,
  replyAuthorLabel,
  replyParentCommentUnavailable,
  replyParentMessageUnavailable,
  scrollToReplyTarget,
  truncateReplyPreview,
  type ReplyParentCommentLike,
  type ReplyParentMessageLike,
} from "@/lib/replyReference"

type ReplyReferenceBlockProps = {
  parentMessageId?: string | null
  parentCommentId?: string | null
  parentMessage?: ReplyParentMessageLike | null
  parentComment?: ReplyParentCommentLike | null
  targetElementId: string
  onJumpToParent?: () => boolean
  onUnavailable?: () => void
  className?: string
}

export default function ReplyReferenceBlock({
  parentMessageId,
  parentCommentId,
  parentMessage,
  parentComment,
  targetElementId,
  onJumpToParent,
  onUnavailable,
  className = "",
}: ReplyReferenceBlockProps) {
  const messageUnavailable = replyParentMessageUnavailable(
    parentMessageId,
    parentMessage
  )
  const commentUnavailable = replyParentCommentUnavailable(
    parentCommentId,
    parentComment
  )

  if (!parentMessageId && !parentCommentId) return null

  if (messageUnavailable || commentUnavailable) {
    return (
      <p className={`text-xs italic text-gray-500 ${className}`}>
        Original message unavailable
      </p>
    )
  }

  const authorName = parentMessage
    ? replyAuthorLabel(parentMessage.profiles)
    : replyAuthorLabel(parentComment?.profiles)
  const preview = parentMessage
    ? previewTextFromMessage(parentMessage)
    : previewTextFromComment(parentComment ?? {})
  const clipped = truncateReplyPreview(preview)

  return (
    <button
      type="button"
      onClick={(e) => {
        e.stopPropagation()
        const ok = onJumpToParent?.() ?? scrollToReplyTarget(targetElementId)
        if (!ok) onUnavailable?.()
      }}
      className={`mb-1.5 w-full rounded border-l-2 border-white/25 bg-black/25 px-2 py-1.5 text-left transition hover:bg-black/40 ${className}`}
    >
      <p className="truncate text-xs font-medium text-gray-300">{authorName}</p>
      {clipped ? (
        <p className="mt-0.5 line-clamp-2 text-xs text-gray-500">{clipped}</p>
      ) : null}
    </button>
  )
}
