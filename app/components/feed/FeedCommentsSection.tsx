"use client"

import {
  memo,
  useCallback,
  useRef,
  useState,
  type MutableRefObject,
  type RefObject,
} from "react"
import FeedCommentComposer from "./FeedCommentComposer"
import FeedCommentList from "./FeedCommentList"

type FeedCommentsSectionProps = {
  post: any
  user: any
  comments: any[]
  commentSubmitting: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  onSubmitComment: (post: any, text: string) => Promise<boolean>
  /** Scroll container for the comment list only (modal layout). */
  listScrollRef?: RefObject<HTMLDivElement | null>
}

function FeedCommentsSection({
  post,
  user,
  comments,
  commentSubmitting,
  draftSyncRef,
  onSubmitComment,
  listScrollRef,
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

  const composer = user ? (
    <FeedCommentComposer
      post={post}
      user={user}
      commentValue={commentDraft}
      commentSubmitting={commentSubmitting}
      onCommentChange={handleCommentChange}
      onSubmitComment={handleSubmitComment}
    />
  ) : null

  if (listScrollRef) {
    return (
      <div
        className="flex min-h-0 flex-1 flex-col overflow-hidden px-4 pb-4 pt-3"
        onClick={stopPropagation}
        onKeyDown={stopPropagation}
      >
        <div
          ref={listScrollRef}
          className="min-h-0 flex-1 overflow-y-auto overscroll-contain"
        >
          <FeedCommentList comments={comments} />
        </div>
        {composer ? <div className="shrink-0 pt-3">{composer}</div> : null}
      </div>
    )
  }

  return (
    <div
      className="mt-2 space-y-3 border-t border-white/10 px-4 pb-4 pt-3"
      onClick={stopPropagation}
      onKeyDown={stopPropagation}
    >
      <FeedCommentList comments={comments} />
      {composer}
    </div>
  )
}

export default memo(FeedCommentsSection)
