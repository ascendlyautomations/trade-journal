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

type FeedCommentsSectionProps = {
  post: any
  user: any
  comments: any[]
  commentSubmitting: boolean
  draftSyncRef?: MutableRefObject<Record<string, string>>
  onSubmitComment: (
    post: any,
    text: string,
    parentCommentId?: string | null
  ) => Promise<boolean>
  onDeleteComment?: (comment: any) => Promise<boolean>
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
  onDeleteComment,
  listScrollRef,
}: FeedCommentsSectionProps) {
  const pid = String(post.id)
  const [commentDraft, setCommentDraft] = useState(
    () => draftSyncRef?.current[pid] ?? ""
  )
  const [replyTarget, setReplyTarget] = useState<CommentReplyTarget | null>(null)
  const [pendingDelete, setPendingDelete] = useState<any>(null)
  const [deleteBusy, setDeleteBusy] = useState(false)
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
      if (commentSubmitting) return
      const text = commentDraftRef.current.trim()
      if (!text) return
      const ok = await onSubmitComment(
        p,
        text,
        replyTarget?.parentCommentId ?? null
      )
      if (ok) {
        setCommentDraft("")
        setReplyTarget(null)
        if (draftSyncRef) {
          draftSyncRef.current[pid] = ""
        }
      }
    },
    [
      commentSubmitting,
      draftSyncRef,
      onSubmitComment,
      pid,
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
        inputId: `comment-input-${pid}`,
        onDraftSync: (value) => {
          if (draftSyncRef) {
            draftSyncRef.current[pid] = value
          }
        },
      })
    },
    [comments, draftSyncRef, pid]
  )

  const handleCancelReply = useCallback(() => {
    clearCommentReplyDraft({
      setReplyTarget,
      setDraft: setCommentDraft,
      onDraftSync: (value) => {
        if (draftSyncRef) {
          draftSyncRef.current[pid] = value
        }
      },
    })
  }, [draftSyncRef, pid])

  const handleConfirmDelete = useCallback(async () => {
    if (!pendingDelete || !onDeleteComment) {
      console.warn("[comment-delete] confirm skipped", {
        hasPending: pendingDelete != null,
        hasHandler: onDeleteComment != null,
      })
      return
    }

    console.log("[comment-delete] confirm", {
      commentId: String(pendingDelete.id),
      postId: pendingDelete.post_id ?? post.id,
      userId: pendingDelete.user_id,
    })

    setDeleteBusy(true)
    try {
      const commentForDelete = {
        ...pendingDelete,
        post_id: pendingDelete.post_id ?? post.id,
      }
      const ok = await onDeleteComment(commentForDelete)
      console.log("[comment-delete] handler finished", {
        commentId: String(pendingDelete.id),
        ok,
      })
      if (ok) setPendingDelete(null)
    } finally {
      setDeleteBusy(false)
    }
  }, [onDeleteComment, pendingDelete, post.id])

  const stopPropagation = useCallback((e: React.SyntheticEvent) => {
    e.stopPropagation()
  }, [])

  const composer = user ? (
    <FeedCommentComposer
      post={post}
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
      onReply={handleReply}
      onRequestDelete={
        onDeleteComment
          ? (comment) =>
              setPendingDelete({
                ...comment,
                post_id: comment.post_id ?? post.id,
              })
          : undefined
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
