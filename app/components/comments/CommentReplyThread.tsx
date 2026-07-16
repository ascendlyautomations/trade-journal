"use client"

import { memo, useState } from "react"
import { getReplyThreadDisplay } from "@/lib/commentThreads"
import FeedCommentItem from "@/app/components/feed/FeedCommentItem"
import type { CommentLikeMeta } from "@/lib/commentLikes"

type CommentReplyThreadProps = {
  replies: any[]
  topLevelCommentCount: number
  mentionUserIdsByUsername: Map<string, string>
  currentUserId?: string | null
  contentOwnerUserId?: string | null
  replyAvatarClassName?: string
  likesByCommentId?: Record<string, CommentLikeMeta>
  onToggleCommentLike?: (comment: any) => void
  isCommentLikeBusy?: (commentId: string) => boolean
  onReply?: (comment: any) => void
  onRequestDelete?: (comment: any) => void
  onTogglePin?: (comment: any, pinned: boolean) => void
  deleteMenuClassName?: string
}

function CommentReplyThread({
  replies,
  topLevelCommentCount,
  mentionUserIdsByUsername,
  currentUserId,
  contentOwnerUserId,
  replyAvatarClassName = "h-6 w-6 shrink-0 rounded-full object-cover",
  likesByCommentId,
  onToggleCommentLike,
  isCommentLikeBusy,
  onReply,
  onRequestDelete,
  onTogglePin,
  deleteMenuClassName,
}: CommentReplyThreadProps) {
  const [expanded, setExpanded] = useState(false)

  if (replies.length === 0) return null

  const { visibleReplies, showToggle, collapsedLabel } = getReplyThreadDisplay(
    replies,
    topLevelCommentCount,
    expanded
  )

  return (
    <div className="mt-1.5 space-y-2 border-l border-white/5 pl-3 sm:pl-4">
      <div className="space-y-2 overflow-hidden transition-[max-height,opacity] duration-300 ease-out">
        {visibleReplies.map((reply) => (
          <FeedCommentItem
            key={String(reply.id)}
            comment={reply}
            mentionUserIdsByUsername={mentionUserIdsByUsername}
            currentUserId={currentUserId}
            contentOwnerUserId={contentOwnerUserId}
            avatarClassName={replyAvatarClassName}
            likeMeta={likesByCommentId?.[String(reply.id)]}
            onToggleLike={onToggleCommentLike}
            likeDisabled={isCommentLikeBusy?.(String(reply.id)) ?? false}
            onReply={onReply}
            onRequestDelete={onRequestDelete}
            onTogglePin={onTogglePin}
            deleteMenuClassName={deleteMenuClassName}
          />
        ))}
      </div>

      {showToggle ? (
        <button
          type="button"
          onClick={() => setExpanded((prev) => !prev)}
          className="text-xs font-medium text-gray-400 transition hover:text-gray-300"
        >
          {expanded ? "Hide replies" : collapsedLabel}
        </button>
      ) : null}
    </div>
  )
}

export default memo(CommentReplyThread)
