"use client"

import { memo, useCallback, useRef, useState, type MutableRefObject } from "react"
import FeedCommentComposer from "./FeedCommentComposer"
import FeedCommentList from "./FeedCommentList"

type FeedCommentsSectionProps = {
  post: any
  user: any
  comments: any[]
  commentSubmitting: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  onSubmitComment: (post: any, text: string) => Promise<boolean>
}

function FeedCommentsSection({
  post,
  user,
  comments,
  commentSubmitting,
  draftSyncRef,
  onSubmitComment,
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

  const stopPropagation = useCallback((e: React.SyntheticEvent) => {
    e.stopPropagation()
  }, [])

  return (
    <div
      className="space-y-3 border-t border-white/10 pt-3 px-4 pb-4 mt-2"
      onClick={stopPropagation}
      onKeyDown={stopPropagation}
    >
      <FeedCommentList comments={comments} />
      {user ? (
        <FeedCommentComposer
          post={post}
          user={user}
          commentValue={commentDraft}
          commentSubmitting={commentSubmitting}
          onCommentChange={handleCommentChange}
          onSubmitComment={handleSubmitComment}
        />
      ) : null}
    </div>
  )
}

export default memo(FeedCommentsSection)
