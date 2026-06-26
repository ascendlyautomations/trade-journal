"use client"

import { memo } from "react"
import { ProfileAvatarLink } from "@/app/components/ProfileLink"
import { CommentAuthorLine } from "@/app/components/comments/CommentAuthorLine"
import CommentDeleteMenu from "@/app/components/comments/CommentDeleteMenu"
import CommentContent from "@/app/components/comments/CommentContent"
import ReplyActionButton from "@/app/components/replies/ReplyActionButton"
import { commentElementId } from "@/lib/replyReference"

type FeedCommentItemProps = {
  comment: any
  mentionUserIdsByUsername?: Map<string, string>
  currentUserId?: string | null
  avatarClassName?: string
  stopPropagation?: boolean
  onReply?: (comment: any) => void
  onRequestDelete?: (comment: any) => void
  deleteMenuClassName?: string
}

function FeedCommentItem({
  comment,
  mentionUserIdsByUsername,
  currentUserId,
  avatarClassName = "h-8 w-8 shrink-0 rounded-full object-cover",
  stopPropagation = false,
  onReply,
  onRequestDelete,
  deleteMenuClassName,
}: FeedCommentItemProps) {
  const userId = String(comment.user_id ?? "")
  const username = comment.profiles?.username
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
          {canDelete ? (
            <div className="flex shrink-0 items-center">
              <CommentDeleteMenu
                menuClassName={deleteMenuClassName}
                onDelete={() => {
                  console.log("[comment-delete] clicked", String(comment.id))
                  onRequestDelete(comment)
                }}
              />
            </div>
          ) : null}
        </div>
        <CommentContent
          content={String(comment.content ?? "")}
          mentionUserIdsByUsername={mentionUserIdsByUsername}
          stopPropagation={stopPropagation}
        />
        {onReply ? (
          <ReplyActionButton
            onReply={() => onReply(comment)}
            className="mt-0.5 px-0 py-0"
          />
        ) : null}
      </div>
    </div>
  )
}

export default memo(FeedCommentItem)
