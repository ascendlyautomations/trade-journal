"use client"

import { memo } from "react"
import { ProfileAvatarLink } from "@/app/components/ProfileLink"
import { CommentAuthorLine } from "@/app/components/comments/CommentAuthorLine"
import CommentDeleteMenu from "@/app/components/comments/CommentDeleteMenu"
import ReplyActionButton from "@/app/components/replies/ReplyActionButton"
import ReplyReferenceBlock from "@/app/components/replies/ReplyReferenceBlock"
import {
  commentElementId,
  type ReplyParentCommentLike,
} from "@/lib/replyReference"

type FeedCommentItemProps = {
  comment: any
  parentComment?: ReplyParentCommentLike | null
  currentUserId?: string | null
  avatarClassName?: string
  stopPropagation?: boolean
  onReply?: (comment: any) => void
  onReplyUnavailable?: () => void
  onRequestDelete?: (comment: any) => void
  deleteMenuClassName?: string
}

function FeedCommentItem({
  comment,
  parentComment,
  currentUserId,
  avatarClassName = "h-8 w-8 shrink-0 rounded-full object-cover",
  stopPropagation = false,
  onReply,
  onReplyUnavailable,
  onRequestDelete,
  deleteMenuClassName,
}: FeedCommentItemProps) {
  const userId = String(comment.user_id ?? "")
  const username = comment.profiles?.username
  const parent =
    parentComment ??
    (comment.parent as ReplyParentCommentLike | null | undefined)
  const canDelete =
    currentUserId != null &&
    onRequestDelete != null &&
    String(currentUserId) === userId

  return (
    <div
      id={commentElementId(String(comment.id))}
      className="group flex items-start gap-2"
    >
      <ProfileAvatarLink
        userId={userId}
        username={username}
        src={comment.profiles?.avatar_url}
        imgClassName={avatarClassName}
        stopPropagation={stopPropagation}
      />
      <div className="min-w-0 flex-1">
        <div className="flex items-start gap-1">
          <div className="min-w-0 flex-1">
            <CommentAuthorLine
              userId={userId}
              username={username}
              createdAt={comment.created_at}
              stopPropagation={stopPropagation}
            />
          </div>
          <div className="flex shrink-0 items-center gap-0.5">
            {onReply ? (
              <ReplyActionButton onReply={() => onReply(comment)} />
            ) : null}
            {canDelete ? (
              <CommentDeleteMenu
                menuClassName={deleteMenuClassName}
                onDelete={() => {
                  console.log("[comment-delete] clicked", String(comment.id))
                  onRequestDelete(comment)
                }}
              />
            ) : null}
          </div>
        </div>
        {comment.parent_comment_id ? (
          <ReplyReferenceBlock
            parentCommentId={comment.parent_comment_id}
            parentComment={parent}
            targetElementId={commentElementId(String(parent?.id ?? comment.parent_comment_id))}
            onUnavailable={onReplyUnavailable}
          />
        ) : null}
        <p className="break-words text-sm text-white">{comment.content}</p>
      </div>
    </div>
  )
}

export default memo(FeedCommentItem)
