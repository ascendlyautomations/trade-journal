"use client"

import { useCallback, useRef, useState, type MutableRefObject } from "react"
import { PostInteractionsComments } from "@/app/components/PostInteractions"
import type { FeedLikeMeta } from "./FeedPostCard"

type FeedCommentsSectionProps = {
  post: any
  user: any
  comments: any[]
  likeMeta: FeedLikeMeta
  commentsOpen: boolean
  commentSubmitting: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  onToggleLike: (post: any) => void
  onToggleComments: (postId: string) => void
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  onSharePost: (post: any) => void
}

function FeedCommentsSection({
  post,
  user,
  comments,
  likeMeta,
  commentsOpen,
  commentSubmitting,
  draftSyncRef,
  onToggleLike,
  onToggleComments,
  onSubmitComment,
  onSharePost,
}: FeedCommentsSectionProps) {
  const pid = String(post.id)
  const [commentDraft, setCommentDraft] = useState(
    () => draftSyncRef?.current[pid] ?? ""
  )
  const commentDraftRef = useRef(commentDraft)
  commentDraftRef.current = commentDraft

  const handleCommentChange = useCallback(
    (_postId: string, value: string) => {
      setCommentDraft(value)
      if (draftSyncRef) {
        draftSyncRef.current[pid] = value
      }
    },
    [draftSyncRef, pid]
  )

  const handleSubmitComment = useCallback(
    async (p: any) => {
      const text = commentDraftRef.current.trim()
      if (!text) return
      const ok = await onSubmitComment(p, text)
      if (ok) {
        setCommentDraft("")
        if (draftSyncRef) {
          draftSyncRef.current[pid] = ""
        }
      }
    },
    [draftSyncRef, onSubmitComment, pid]
  )

  return (
    <PostInteractionsComments
      post={post}
      user={user}
      comments={comments}
      likeMeta={likeMeta}
      commentsOpen={commentsOpen}
      commentValue={commentDraft}
      commentSubmitting={commentSubmitting}
      onToggleLike={onToggleLike}
      onToggleComments={onToggleComments}
      onCommentChange={handleCommentChange}
      onSubmitComment={handleSubmitComment}
      onSharePost={onSharePost}
      stopPropagation
      className="px-4 pb-4 mt-2"
    />
  )
}

export default FeedCommentsSection
