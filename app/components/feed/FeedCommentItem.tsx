"use client"

import { memo } from "react"
import { ProfileAvatarLink } from "@/app/components/ProfileLink"
import { CommentAuthorLine } from "@/app/components/comments/CommentAuthorLine"
import CommentActionsMenu from "@/app/components/comments/CommentDeleteMenu"
import CommentContent from "@/app/components/comments/CommentContent"
import { devLog } from "@/lib/devLog"
import CommentLikeActionButton from "@/app/components/comments/CommentLikeActionButton"
import ReplyActionButton from "@/app/components/replies/ReplyActionButton"
import { commentElementId } from "@/lib/replyReference"
import type { CommentLikeMeta } from "@/lib/commentLikes"
import { canPinComment, isCommentPinned } from "@/lib/pinComment"

type FeedCommentItemProps = {
  comment: any
  mentionUserIdsByUsername?: Map<string, string>
  currentUserId?: string | null
  contentOwnerUserId?: string | null
  avatarClassName?: string
  stopPropagation?: boolean
  likeMeta?: CommentLikeMeta
  onToggleLike?: (comment: any) => void
  likeDisabled?: boolean
  onReply?: (comment: any) => void
  onRequestDelete?: (comment: any) => void
  onTogglePin?: (comment: any, pinned: boolean) => void
  deleteMenuClassName?: string
}

function FeedCommentItem({
  comment,
  mentionUserIdsByUsername,
  currentUserId,
  contentOwnerUserId,
  avatarClassName = "h-8 w-8 shrink-0 rounded-full object-cover",
  stopPropagation = false,
  likeMeta,
  onToggleLike,
  likeDisabled = false,
  onReply,
  onRequestDelete,
  onTogglePin,
  deleteMenuClassName,
}: FeedCommentItemProps) {
  const userId = String(comment.user_id ?? "")
  const username = comment.profiles?.username
  const isTopLevel = comment.parent_comment_id == null
  const pinned = isCommentPinned(comment)
  const canPin =
    isTopLevel &&
    onTogglePin != null &&
    canPinComment({
      viewerUserId: currentUserId,
      contentOwnerUserId,
    })
  const canDelete =
    currentUserId != null &&
    onRequestDelete != null &&
    String(currentUserId) === userId
  const showMenu = canPin || canDelete

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
        {pinned && isTopLevel ? (
          <div className="mb-0.5 flex items-center gap-1 text-[11px] font-medium tracking-wide text-gray-400">
            <span aria-hidden>📌</span>
            <span>Pinned</span>
          </div>
        ) : null}
        <div className="flex items-start gap-1">
          <div className="min-w-0 flex-1">
            <CommentAuthorLine
              userId={userId}
              username={username}
              createdAt={comment.created_at}
              stopPropagation={stopPropagation}
            />
          </div>
          {showMenu ? (
            <div className="flex shrink-0 items-center">
              <CommentActionsMenu
                menuClassName={deleteMenuClassName}
                canPin={canPin}
                isPinned={pinned}
                canDelete={canDelete}
                onPin={() => {
                  devLog("[comment-pin] pin", String(comment.id))
                  onTogglePin?.(comment, true)
                }}
                onUnpin={() => {
                  devLog("[comment-pin] unpin", String(comment.id))
                  onTogglePin?.(comment, false)
                }}
                onDelete={() => {
                  devLog("[comment-delete] clicked", String(comment.id))
                  onRequestDelete?.(comment)
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
        {onToggleLike ? (
          <div className="mt-0.5 flex items-center gap-3">
            <CommentLikeActionButton
              meta={likeMeta ?? { count: 0, liked: false }}
              disabled={likeDisabled}
              onToggle={() => onToggleLike(comment)}
              className="px-0 py-0"
            />
            {onReply ? (
              <ReplyActionButton
                onReply={() => onReply(comment)}
                className="px-0 py-0"
              />
            ) : null}
          </div>
        ) : onReply ? (
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
