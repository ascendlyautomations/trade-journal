"use client"

import { memo, useState } from "react"
import { getReplyThreadDisplay } from "@/lib/commentThreads"
import FeedCommentItem from "@/app/components/feed/FeedCommentItem"

type CommentReplyThreadProps = {
  replies: any[]
  topLevelCommentCount: number
  mentionUserIdsByUsername: Map<string, string>
  currentUserId?: string | null
  replyAvatarClassName?: string
  onReply?: (comment: any) => void
  onRequestDelete?: (comment: any) => void
  deleteMenuClassName?: string
}

function CommentReplyThread({
  replies,
  topLevelCommentCount,
  mentionUserIdsByUsername,
  currentUserId,
  replyAvatarClassName = "h-6 w-6 shrink-0 rounded-full object-cover",
  onReply,
  onRequestDelete,
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
            avatarClassName={replyAvatarClassName}
            onReply={onReply}
            onRequestDelete={onRequestDelete}
            deleteMenuClassName={deleteMenuClassName}
          />
        ))}
      </div>

      {showToggle ? (
        <button
          type="button"
          onClick={() => setExpanded((prev) => !prev)}
          className="text-xs font-medium text-gray-500 transition hover:text-gray-300"
        >
          {expanded ? "Hide replies" : collapsedLabel}
        </button>
      ) : null}
    </div>
  )
}

export default memo(CommentReplyThread)
