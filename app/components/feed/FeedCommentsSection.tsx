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
import ConfirmModal from "@/app/components/ui/ConfirmModal"
import {
  clearCommentReplyDraft,
  startCommentReply,
  type CommentReplyTarget,
} from "@/lib/commentReplyUx"
import {
  commentLikeNotificationParentFromFeedPost,
  commentLikeSourceFromFeedPost,
} from "@/lib/commentLikes"
import { useCommentLikes } from "@/lib/useCommentLikes"
import type { FeedCommentTarget } from "./feedPostHelpers"

type FeedCommentsSectionProps = {
  target: FeedCommentTarget
  user: any
  comments: any[]
  commentSubmitting: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  onSubmitComment: (
    submitContext: unknown,
    text: string,
    parentCommentId?: string | null
  ) => Promise<boolean>
  onDeleteComment?: (comment: any) => Promise<boolean>
  /** Scroll container for the comment list only (modal layout). */
  listScrollRef?: RefObject<HTMLDivElement | null>
}

function FeedCommentsSection({
  target,
  user,
  comments,
  commentSubmitting,
  draftSyncRef,
  onSubmitComment,
  onDeleteComment,
  listScrollRef,
}: FeedCommentsSectionProps) {
  const contentId = target.contentId
  const submitContext =
    target.submitContext && typeof target.submitContext === "object"
      ? (target.submitContext as Record<string, unknown>)
      : null
  const commentLikeSource = submitContext
    ? commentLikeSourceFromFeedPost(submitContext)
    : null
  const commentLikeNotificationParent = submitContext
    ? commentLikeNotificationParentFromFeedPost(submitContext)
    : {}

  const { likesByCommentId, toggleCommentLikeFor, isCommentLikeBusy, canLikeComments } =
    useCommentLikes({
      source: commentLikeSource,
      comments,
      currentUserId: user?.id,
      notificationParent: commentLikeNotificationParent,
    })

  const [commentDraft, setCommentDraft] = useState(
    () => draftSyncRef?.current[contentId] ?? ""
  )
  const [replyTarget, setReplyTarget] = useState<CommentReplyTarget | null>(null)
  const [pendingDelete, setPendingDelete] = useState<any>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
  const commentDraftRef = useRef(commentDraft)
  commentDraftRef.current = commentDraft

  const handleCommentChange = useCallback(
    (_contentId: string, value: string) => {
      setCommentDraft(value)
      if (draftSyncRef) {
        draftSyncRef.current[contentId] = value
      }
    },
    [contentId, draftSyncRef]
  )

  const handleSubmitComment = useCallback(
    async (submitContext: unknown) => {
      if (commentSubmitting) return
      const text = commentDraftRef.current.trim()
      if (!text) return
      const ok = await onSubmitComment(
        submitContext,
        text,
        replyTarget?.parentCommentId ?? null
      )
      if (ok) {
        setCommentDraft("")
        setReplyTarget(null)
        if (draftSyncRef) {
          draftSyncRef.current[contentId] = ""
        }
      }
    },
    [
      commentSubmitting,
      contentId,
      draftSyncRef,
      onSubmitComment,
      replyTarget?.parentCommentId,
    ]
  )

  const handleReply = useCallback(
    (comment: any) => {
      startCommentReply({
        comment,
        allComments: comments,
        setReplyTarget,
        setDraft: setCommentDraft,
        inputId: `comment-input-${contentId}`,
        onDraftSync: (value) => {
          if (draftSyncRef) {
            draftSyncRef.current[contentId] = value
          }
        },
      })
    },
    [comments, contentId, draftSyncRef]
  )

  const handleCancelReply = useCallback(() => {
    clearCommentReplyDraft({
      setReplyTarget,
      setDraft: setCommentDraft,
      onDraftSync: (value) => {
        if (draftSyncRef) {
          draftSyncRef.current[contentId] = value
        }
      },
    })
  }, [contentId, draftSyncRef])

  const handleConfirmDelete = useCallback(async () => {
    if (!pendingDelete || !onDeleteComment) {
      console.warn("[comment-delete] confirm skipped", {
        hasPending: pendingDelete != null,
        hasHandler: onDeleteComment != null,
      })
      return
    }

    setDeleteBusy(true)
    try {
      const ok = await onDeleteComment(pendingDelete)
      if (ok) setPendingDelete(null)
    } finally {
      setDeleteBusy(false)
    }
  }, [onDeleteComment, pendingDelete])

  const stopPropagation = useCallback((e: React.SyntheticEvent) => {
    e.stopPropagation()
  }, [])

  const composer = user ? (
    <FeedCommentComposer
      contentId={contentId}
      submitContext={target.submitContext}
      user={user}
      commentValue={commentDraft}
      commentSubmitting={commentSubmitting}
      replyTarget={replyTarget}
      onCancelReply={handleCancelReply}
      onCommentChange={handleCommentChange}
      onSubmitComment={handleSubmitComment}
    />
  ) : null

  const commentList = (
    <FeedCommentList
      comments={comments}
      currentUserId={user?.id}
      likesByCommentId={likesByCommentId}
      onToggleCommentLike={canLikeComments ? toggleCommentLikeFor : undefined}
      isCommentLikeBusy={isCommentLikeBusy}
      onReply={handleReply}
      onRequestDelete={
        onDeleteComment ? (comment) => setPendingDelete(comment) : undefined
      }
      deleteMenuClassName="z-[9100]"
    />
  )

  const deleteModal = onDeleteComment ? (
    <ConfirmModal
      open={pendingDelete != null}
      title="Delete Comment?"
      description="This action cannot be undone."
      confirmLabel="Delete"
      destructive
      loading={deleteBusy}
      onCancel={() => {
        if (!deleteBusy) setPendingDelete(null)
      }}
      onConfirm={handleConfirmDelete}
    />
  ) : null

  if (listScrollRef) {
    const hasComments = comments.length > 0

    return (
      <div
        className="flex min-h-0 flex-1 flex-col overflow-hidden px-4 pb-4 pt-2"
        onClick={stopPropagation}
        onKeyDown={stopPropagation}
      >
        <div
          ref={listScrollRef}
          className={
            hasComments
              ? "min-h-0 flex-1 overflow-y-auto overscroll-contain"
              : "shrink-0"
          }
        >
          {hasComments ? (
            commentList
          ) : (
            <p className="text-sm text-white/40">No comments yet.</p>
          )}
        </div>
        {composer ? <div className="shrink-0 pt-2">{composer}</div> : null}
        {deleteModal}
      </div>
    )
  }

  return (
    <div
      className="mt-2 space-y-3 border-t border-white/10 px-4 pb-4 pt-3"
      onClick={stopPropagation}
      onKeyDown={stopPropagation}
    >
      {commentList}
      {composer}
      {deleteModal}
    </div>
  )
}

export default memo(FeedCommentsSection)
